mod debug_alloc
# Allocation tracking wrapper with leak inspection and invalid-free rejection.

use "std:allocator" as allocator
use "std:errors" as errors
use "std:memory" as memory
use "std:cast" as cast

const DEFAULT_CAPACITY u64 = 256

Entry(
    pointer u8*
    size u64
    active bool
)

# Construction options for a debug allocator.
pub Options(
    initialCapacity u64
    canGrow bool
    rejectUntrackedFree bool
)

# Snapshot of allocation counters. Metadata bytes describe the current tracking
# table and are not included in liveBytes.
pub Stats(
    liveAllocations u64
    peakAllocations u64
    liveBytes u64
    peakBytes u64
    metadataBytes u64
    allocationCalls u64
    reallocationCalls u64
    freeCalls u64
    rejectedFrees u64
    rejectedReallocations u64
)

# One currently live allocation.
pub Leak(
    pointer u8*
    size u64
)

# Owned tracking state wrapping a borrowed target allocator.
pub DebugAllocator impl allocator.Allocator(
    target allocator.Allocator*
    entries Entry*
    capacityValue u64
    count u64
    options Options
    liveBytesValue u64
    peakCount u64
    peakBytesValue u64
    allocationCallsValue u64
    reallocationCallsValue u64
    freeCallsValue u64
    rejectedFreesValue u64
    rejectedReallocationsValue u64
)

findEntry(debug DebugAllocator*, pointer u8*) Entry*:
    for i u64 = 0 to debug.capacityValue:
        # SAFETY: entries is allocated for capacityValue Entry objects.
        unsafe:
            if debug.entries[i].active && debug.entries[i].pointer == pointer:
                ret addrof debug.entries[i]
            ..
        ..
    ..
    ret none
..

findFreeEntry(debug DebugAllocator*) Entry*:
    for i u64 = 0 to debug.capacityValue:
        # SAFETY: entries is allocated for capacityValue Entry objects.
        unsafe:
            if debug.entries[i].active == false:
                ret addrof debug.entries[i]
            ..
        ..
    ..
    ret none
..

grow(debug DebugAllocator*) !void:
    target := debug.target
    if debug.options.canGrow == false:
        throw errors.outOfMemory("debug allocator tracking capacity exhausted")
    ..
    maxU64 u64 = 0 - 1
    if debug.capacityValue > maxU64 / 2:
        throw errors.wouldOverflow("debug allocator tracking capacity overflow")
    ..
    newCapacity := debug.capacityValue * 2
    if sizeof Entry != 0 && newCapacity > maxU64 / sizeof Entry:
        throw errors.wouldOverflow("debug allocator metadata size overflow")
    ..
    newEntries := try target.allocT[Entry](newCapacity)
    memory.zero(newEntries, newCapacity * sizeof Entry)
    i u64 = 0
    writeIndex u64 = 0
    loop i < debug.capacityValue:
        # SAFETY: both metadata arrays have their recorded capacities; writeIndex
        # never exceeds the number of active entries already visited.
        unsafe:
            if debug.entries[i].active:
                newEntries[writeIndex] = debug.entries[i]
                writeIndex = writeIndex + 1
            ..
        ..
        i = i + 1
    ..
    target.free(debug.entries)
    debug.entries = newEntries
    debug.capacityValue = newCapacity
..

reserveEntry(debug DebugAllocator*) !Entry*:
    entry := findFreeEntry(debug)
    if entry != none:
        ret entry
    ..
    try grow(debug)
    ret findFreeEntry(debug)
..

record(debug DebugAllocator*, entry Entry*, pointer u8*, size u64) void:
    entry.pointer = pointer
    entry.size = size
    entry.active = true
    debug.count = debug.count + 1
    debug.liveBytesValue = debug.liveBytesValue + size
    if debug.count > debug.peakCount:
        debug.peakCount = debug.count
    ..
    if debug.liveBytesValue > debug.peakBytesValue:
        debug.peakBytesValue = debug.liveBytesValue
    ..
..

debugAlloc(raw ptr, byteCount u64) !u8*:
    debug DebugAllocator*
    # SAFETY: allocator callbacks receive the DebugAllocator installed by allocator().
    unsafe:
        debug = raw
    ..
    if byteCount == 0:
        throw errors.invalidArgument("debug allocation size must be greater than zero")
    ..
    entry := try reserveEntry(debug)
    target := debug.target
    pointer := try target.alloc(byteCount)
    record(debug, entry, pointer, byteCount)
    debug.allocationCallsValue = debug.allocationCallsValue + 1
    ret pointer
..

debugFree(raw ptr, pointer u8*) void:
    if pointer == none:
        ret
    ..
    debug DebugAllocator*
    # SAFETY: allocator callbacks receive the DebugAllocator installed by allocator().
    unsafe:
        debug = raw
    ..
    entry := findEntry(debug, pointer)
    target := debug.target
    if entry == none:
        debug.rejectedFreesValue = debug.rejectedFreesValue + 1
        if debug.options.rejectUntrackedFree == false:
            target.free(pointer)
            debug.freeCallsValue = debug.freeCallsValue + 1
        ..
        ret
    ..
    size := entry.size
    target.free(pointer)
    entry.pointer = none
    entry.size = 0
    entry.active = false
    debug.count = debug.count - 1
    debug.liveBytesValue = debug.liveBytesValue - size
    debug.freeCallsValue = debug.freeCallsValue + 1
..

debugRealloc(raw ptr, pointer u8*, byteCount u64) !u8*:
    debug DebugAllocator*
    # SAFETY: allocator callbacks receive the DebugAllocator installed by allocator().
    unsafe:
        debug = raw
    ..
    if pointer == none:
        ret try debugAlloc(raw, byteCount)
    ..
    if byteCount == 0:
        throw errors.invalidArgument("debug allocation size must be greater than zero")
    ..
    entry := findEntry(debug, pointer)
    if entry == none:
        debug.rejectedReallocationsValue = debug.rejectedReallocationsValue + 1
        throw errors.invalidArgument("block is not tracked by debug allocator")
    ..
    oldSize := entry.size
    target := debug.target
    replacement := try target.realloc(pointer, byteCount)
    entry.pointer = replacement
    entry.size = byteCount
    if byteCount >= oldSize:
        debug.liveBytesValue = debug.liveBytesValue + (byteCount - oldSize)
    else:
        debug.liveBytesValue = debug.liveBytesValue - (oldSize - byteCount)
    ..
    if debug.liveBytesValue > debug.peakBytesValue:
        debug.peakBytesValue = debug.liveBytesValue
    ..
    debug.reallocationCallsValue = debug.reallocationCallsValue + 1
    ret replacement
..

DebugAllocator.alloc(byteCount u64) !$u8*:
    ret try debugAlloc(this, byteCount)
..

DebugAllocator.realloc(pointer ptr, byteCount u64) !$u8*:
    ret try debugRealloc(this, cast.reinterpret[u8](pointer), byteCount)
..

DebugAllocator.free(pointer ptr) void:
    debugFree(this, cast.reinterpret[u8](pointer))
..

# Creates a debug allocator with explicit tracking behavior.
pub new(target allocator.Allocator, options Options) !$DebugAllocator:
    if options.initialCapacity == 0:
        throw errors.invalidArgument("debug allocator capacity must be greater than zero")
    ..
    maxU64 u64 = 0 - 1
    if sizeof Entry != 0 && options.initialCapacity > maxU64 / sizeof Entry:
        throw errors.wouldOverflow("debug allocator metadata size overflow")
    ..
    entries := try target.allocT[Entry](options.initialCapacity)
    onerror target.free(entries)
    memory.zero(entries, options.initialCapacity * sizeof Entry)
    targetPtr := try target.allocT[allocator.Allocator](1)
    unsafe:
        *targetPtr = target
    ..
    ret DebugAllocator(
        target=targetPtr,
        entries=entries,
        capacityValue=options.initialCapacity,
        count=0,
        options=options,
        liveBytesValue=0,
        peakCount=0,
        peakBytesValue=0,
        allocationCallsValue=0,
        reallocationCallsValue=0,
        freeCallsValue=0,
        rejectedFreesValue=0,
        rejectedReallocationsValue=0,
    )
..

# Creates a growing debug allocator with 256 initial entries that rejects
# untracked frees.
pub newDefault(target allocator.Allocator) !$DebugAllocator:
    options := Options(initialCapacity=DEFAULT_CAPACITY, canGrow=true, rejectUntrackedFree=true)
    ret try new(target, options)
..

# Returns a non-owning allocator view. DebugAllocator must remain at a stable
# address and outlive the returned value.
DebugAllocator.allocator() allocator.Allocator:
    ret this.protoBorrow()
..

DebugAllocator.stats() Stats:
    ret Stats(
        liveAllocations=this.count,
        peakAllocations=this.peakCount,
        liveBytes=this.liveBytesValue,
        peakBytes=this.peakBytesValue,
        metadataBytes=this.capacityValue * sizeof Entry,
        allocationCalls=this.allocationCallsValue,
        reallocationCalls=this.reallocationCallsValue,
        freeCalls=this.freeCallsValue,
        rejectedFrees=this.rejectedFreesValue,
        rejectedReallocations=this.rejectedReallocationsValue,
    )
..

DebugAllocator.leakCount() u64:
    ret this.count
..

# Returns the live allocation at a dense leak index from zero to leakCount - 1.
DebugAllocator.leak(index u64) !Leak:
    if index >= this.count:
        throw errors.outOfBounds("debug allocator leak index is out of bounds")
    ..
    seen u64 = 0
    # SAFETY: entries points to capacityValue initialized metadata records.
    unsafe:
        for i u64 = 0 to this.capacityValue:
            if this.entries[i].active:
                if seen == index:
                    ret Leak(pointer=this.entries[i].pointer, size=this.entries[i].size)
                ..
                seen = seen + 1
            ..
        ..
    ..
    throw errors.outOfBounds("debug allocator leak index is out of bounds")
..

# Releases tracking metadata. Live user allocations are intentionally left
# untouched so their pointers are not invalidated implicitly.
destr DebugAllocator.destroy() void:
    target := this.target
    if this.entries != none:
        target.free(this.entries)
    ..
    if this.target != none:
        target.free(this.target)
    ..
    this.target = none
    this.entries = none
    this.capacityValue = 0
..
