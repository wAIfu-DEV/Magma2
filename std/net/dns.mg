mod net_dns
# Parameterized, thread-safe DNS resolver with bounded positive and negative caching.

use "std:allocator" as allocator
use "std:errors" as errors
use "std:memory" as memory
use "std:mutex" as mutex
use "std:slices" as slices
use "std:strings" as strings
use "std:time" as time
use "std:net/address" as address

@platform("windows")
use "std:win/net/dns_impl" as impl

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/net/dns_impl" as impl

pub Options(
    capacity u64
    ttlMs u64
    negativeTtlMs u64
    maxResults u64
)

Entry(
    occupied bool
    hash u64
    host str
    service str
    family u8
    endpoints address.Endpoint*
    count u64
    expiresAtMs u64
    failure error
)

pub Resolver(
    allocator allocator.Allocator
    entries Entry*
    capacity u64
    ttlMs u64
    negativeTtlMs u64
    maxResults u64
    lock mutex.Mutex
    active bool
)

pub defaultOptions() Options:
    ret Options(capacity=256, ttlMs=60000, negativeTtlMs=5000, maxResults=16)
..

pub new(a allocator.Allocator, options Options) !$Resolver:
    if options.capacity == 0 || options.maxResults == 0:
        throw errors.invalidArgument("DNS cache capacity and result limit must be nonzero")
    ..
    entries Entry* = try a.allocT[Entry](options.capacity)
    onerror a.free(entries)
    memory.zero(entries, options.capacity * sizeof Entry)
    guard := try mutex.new()
    ret Resolver(allocator=a, entries=entries, capacity=options.capacity, ttlMs=options.ttlMs, negativeTtlMs=options.negativeTtlMs, maxResults=options.maxResults, lock=move guard, active=true)
..

hashKey(host str, service str, family u8) u64:
    hash u64 = 14695981039346656037
    for i u64 = 0 to host.countBytes():
        hash = (hash ^ strings.byteAt(host, i)) * 1099511628211
    ..
    hash = (hash ^ 255) * 1099511628211
    for i u64 = 0 to service.countBytes():
        hash = (hash ^ strings.byteAt(service, i)) * 1099511628211
    ..
    ret (hash ^ family) * 1099511628211
..

entryAt(resolver Resolver*, index u64) Entry*:
    # SAFETY: callers reduce or compare index against resolver.capacity.
    unsafe:
        ret addrof resolver.entries[index]
    ..
..

matches(entry Entry*, hash u64, host str, service str, family u8) bool:
    ret entry.occupied && entry.hash == hash && entry.family == family && strings.compare(entry.host, host) && strings.compare(entry.service, service)
..

copyResults(source address.Endpoint*, count u64, output address.Endpoint[]) !u64:
    # SAFETY: source contains count cached endpoints and the output guard
    # establishes at least count writable slots.
    unsafe:
    if count > slices.count(output):
        throw errors.wouldOverflow("DNS output buffer is too small")
    ..
    for i u64 = 0 to count:
        output[i] = source[i]
    ..
      ret count
    ..
..

clearEntry(resolver Resolver*, entry Entry*) void:
    # SAFETY: occupied is the ownership bit for host, service, and endpoints;
    # zeroing prevents any second cleanup.
    unsafe:
    if entry.occupied:
        entry.host.free()
        entry.service.free()
        if entry.endpoints != none:
            resolver.allocator.free(entry.endpoints)
        ..
        memory.zero(entry, sizeof Entry)
      ..
    ..
..

findSlot(resolver Resolver*, hash u64, host str, service str, family u8, now u64) u64:
    start u64 = hash % resolver.capacity
    oldestIndex u64 = start
    oldestExpiry u64 = 0 - 1
    for probe u64 = 0 to resolver.capacity:
        index u64 = (start + probe) % resolver.capacity
        entry := entryAt(resolver, index)
        if entry.occupied == false || matches(entry, hash, host, service, family):
            ret index
        ..
        if entry.expiresAtMs <= now:
            ret index
        ..
        if entry.expiresAtMs < oldestExpiry:
            oldestExpiry = entry.expiresAtMs
            oldestIndex = index
        ..
    ..
    ret oldestIndex
..

# Resolves into caller storage. Cache hits perform no allocation or native call.
Resolver.resolveTo(host str, service str, family u8, output address.Endpoint[]) !u64:
    if this.active == false:
        throw errors.invalidArgument("DNS resolver is closed")
    ..
    hash := hashKey(host, service, family)
    now := time.unixTimestampMs()
    try this.lock.lock()
    index := findSlot(this, hash, host, service, family, now)
    cached := entryAt(this, index)
    if matches(cached, hash, host, service, family) && cached.expiresAtMs > now:
        if cached.failure.nok():
            failure := cached.failure
            try this.lock.unlock()
            throw failure
        ..
        count u64, copyError error = copyResults(cached.endpoints, cached.count, output)
        try this.lock.unlock()
        if copyError.nok():
            throw copyError
        ..
        ret count
    ..
    try this.lock.unlock()

    nativeResult impl.Resolved, resolveError error = impl.resolve(host, service, family, this.maxResults)
    resolved address.Endpoint* = none
    resolvedCount u64 = 0
    if resolveError.ok():
        resolved = nativeResult.endpoints
        resolvedCount = nativeResult.count
    ..

    # Populate under the lock. Duplicate concurrent misses are harmless; the
    # last completed lookup replaces the earlier equivalent entry.
    try this.lock.lock()
    now = time.unixTimestampMs()
    index = findSlot(this, hash, host, service, family, now)
    cached = entryAt(this, index)
    clearEntry(this, cached)
    ownedHost str, hostError error = strings.copy(host)
    if hostError.nok():
        try this.lock.unlock()
        if resolved != none:
            this.allocator.free(resolved)
        ..
        throw hostError
    ..
    ownedService str, serviceError error = strings.copy(service)
    if serviceError.nok():
        ownedHost.free()
        try this.lock.unlock()
        if resolved != none:
            this.allocator.free(resolved)
        ..
        throw serviceError
    ..
    cached.occupied = true
    cached.hash = hash
    cached.host = move ownedHost
    cached.service = move ownedService
    cached.family = family
    cached.endpoints = resolved
    cached.count = resolvedCount
    cached.failure = resolveError
    if resolveError.nok():
        cached.expiresAtMs = now + this.negativeTtlMs
    else:
        cached.expiresAtMs = now + this.ttlMs
    ..
    if resolveError.nok():
        failure := resolveError
        try this.lock.unlock()
        throw failure
    ..
    count u64, copyError error = copyResults(cached.endpoints, cached.count, output)
    try this.lock.unlock()
    if copyError.nok():
        throw copyError
    ..
    ret count
..

# Allocating convenience wrapper. Use resolveTo on latency-sensitive paths.
Resolver.resolve(host str, service str, family u8) !$address.Endpoint[]:
    output := try slices.alloc[address.Endpoint](this.maxResults)
    onerror slices.free(output)
    count := try this.resolveTo(host, service, family, output)
    ret slices.fromPtr(slices.toPtr(output), count)
..

Resolver.clear() !void:
    try this.lock.lock()
    for i u64 = 0 to this.capacity:
        clearEntry(this, entryAt(this, i))
    ..
    try this.lock.unlock()
..

destr Resolver.close() !void:
    if this.active:
        try this.clear()
        this.allocator.free(this.entries)
        try this.lock.free()
        this.entries = none
        this.active = false
    ..
..
