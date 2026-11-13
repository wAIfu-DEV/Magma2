mod hash_map
# Allocator-backed string maps with owned generic values.

use "std:allocator" as alc
use "std:hash" as hash
use "std:strings" as strings
use "std:errors" as errors
use "std:memory" as memory
use "std:cast" as cast
use "std:checked" as checked

# Initial capacity for maps expected to start small. Larger registries should
# request a larger capacity explicitly.
pub const DEFAULT_CAPACITY u64 = 4

# Owning string-keyed hash map using open addressing. Keys are copied; values
# are moved into the map and released through cleanup when replaced or removed.
# @warning A HashMap must be freed with the same allocator used to create it.
pub HashMap[T](
    allocator alc.Allocator
    storage ptr
    capacity u64
    length u64
    cleanup fn($T) void
)

keysPtr[T](map HashMap[T]*) str*:
    ret cast.reinterpret[str](map.storage)
..

valuesPtr[T](map HashMap[T]*) T*:
    ret cast.reinterpret[T](cast.utop(cast.ptou(map.storage) + map.capacity * sizeof str))
..

statesPtr[T](map HashMap[T]*) u8*:
    ret cast.reinterpret[u8](cast.utop(cast.ptou(map.storage) + map.capacity * sizeof str + map.capacity * sizeof T))
..

valuesAt[T](storage ptr, capacity u64) T*:
    ret cast.reinterpret[T](cast.utop(cast.ptou(storage) + capacity * sizeof str))
..

statesAt[T](storage ptr, capacity u64) u8*:
    ret cast.reinterpret[u8](cast.utop(cast.ptou(storage) + capacity * sizeof str + capacity * sizeof T))
..

storageSize[T](capacity u64) !u64:
    keysBytes := try checked.byteCount[str](capacity)
    valuesBytes := try checked.byteCount[T](capacity)
    ret try checked.uAdd(try checked.uAdd(keysBytes, valuesBytes), capacity)
..

release[T](cleanup fn($T) void, value $T) void:
    if cleanup == none:
        abandoned := [1]T
        abandoned[0] = move value
        ret
    ..
    cleanup(move value)
..

# Creates an empty map with at least the requested initial capacity.
# @param cleanup optional callback invoked for values still owned by the map
# @complexity O(C) initialization, where C is the normalized capacity
# @ownership The returned map owns its storage and every value passed to set().
# @example
#   users := try hash_map.new[User](a, 16, freeUser)
pub new[T](capacity u64, cleanup fn($T) void) !$HashMap[T]:
    a := ctx.alloc
    if capacity == 0:
        throw errors.invalidArgument("hash map capacity must be positive")
    ..
    storage := try a.alloc(try storageSize[T](capacity))
    memory.zero(statesAt[T](storage, capacity), capacity)
    ret HashMap[T](allocator=a, storage=storage, capacity=capacity, length=0, cleanup=cleanup)
..

# Returns the storage index for key or throws outOfBounds when it is absent.
# @complexity O(1) average, O(N) worst case
# @example
#   index := try users.indexOf("alice")
HashMap[T].indexOf(key str) !u64:
    start := hash.string(key) % this.capacity
    # SAFETY: key/state arrays each contain capacity slots; probing is reduced
    # modulo capacity and only occupied keys are inspected.
    unsafe:
        keys str* = keysPtr[T](this)
        states u8* = statesPtr[T](this)
        for i u64 = 0 to this.capacity:
            idx := (start + i) % this.capacity
            if states[idx] == 0:
                throw errors.failure("key not found in hash map")
            ..
            if states[idx] == 1 && strings.compare(keys[idx], key):
                ret idx
            ..
        ..
    ..
    throw errors.failure("key not found in hash map")
..

# Returns a borrowed copy of the value associated with key.
# @throws outOfBounds if key is absent
# @ownership The map retains ownership; use take() to transfer it.
# @complexity O(1) average, O(N) worst case
# @example
#   user := try users.get("alice")
HashMap[T].get(key str) !T:
    idx := try this.indexOf(key)
    # SAFETY: indexOf returns an occupied value slot within capacity.
    unsafe:
        values T* = valuesPtr[T](this)
        ret values[idx]
    ..
..

# Rebuilds the table at a larger capacity. Owned keys and values are moved
# without copying.
# Rebuilds the table with a larger capacity while preserving all entries.
# @complexity O(N + C), where N is entry count and C is new capacity
# @throws outOfMemory if replacement storage cannot be allocated
# @warning newCapacity must be large enough to contain every current entry.
HashMap[T].resize(newCapacity u64) !void:
    if newCapacity <= this.length:
        throw errors.invalidArgument("hash map capacity is too small")
    ..
    newStorage ptr = try this.allocator.alloc(try storageSize[T](newCapacity))
    # SAFETY: storageSize lays out newCapacity key/value/state slots; occupied
    # old entries are moved once into modulo-bounded empty replacement slots.
    unsafe:
        keys str* = newStorage
        values T* = valuesAt[T](newStorage, newCapacity)
        states u8* = statesAt[T](newStorage, newCapacity)
        memory.zero(states, newCapacity)
        oldKeys str* = keysPtr[T](this)
        oldValues T* = valuesPtr[T](this)
        oldStates u8* = statesPtr[T](this)
        for i u64 = 0 to this.capacity:
            if oldStates[i] == 1:
                start := hash.string(oldKeys[i]) % newCapacity
                probe u64 = 0
                loop probe < newCapacity:
                    idx := (start + probe) % newCapacity
                    if states[idx] == 0:
                        keys[idx] = oldKeys[i]
                        values[idx] = oldValues[i]
                        states[idx] = 1
                        break
                    ..
                    probe = probe + 1
                ..
            ..
        ..
    ..
    this.allocator.free(this.storage)
    this.storage = newStorage
    this.capacity = newCapacity
..

resizeForInsert[T](map HashMap[T]*, newCapacity u64) !bool:
    try map.resize(newCapacity)
    ret true
..

# Inserts item under a copied key, or replaces and cleans up the existing value.
# @ownership Always consumes item, including when allocation or resizing fails.
# @complexity O(1) amortized, O(N) when rebuilding or under heavy collisions
# @example
#   try users.set("alice", user)
HashMap[T].set(key str, item $T) !void:
    onerror release[T](this.cleanup, move item)
    nextLength := try checked.uAdd(this.length, 1)
    loadNumerator := try checked.uMul(nextLength, 4)
    loadLimit := try checked.uMul(this.capacity, 3)
    if loadNumerator >= loadLimit:
        try resizeForInsert[T](this, try checked.uMul(this.capacity, 2))
    ..
    # SAFETY: all probes are modulo capacity; state bytes describe occupancy,
    # and item is transferred only after selecting an empty or occupied slot.
    unsafe:
        keys str* = keysPtr[T](this)
        values T* = valuesPtr[T](this)
        states u8* = statesPtr[T](this)
        start := hash.string(key) % this.capacity
        firstDeleted := this.capacity
        for i u64 = 0 to this.capacity:
            idx := (start + i) % this.capacity
            if states[idx] == 1 && strings.compare(keys[idx], key):
                previous $T = values[idx]
                values[idx] = memory.zeroValue[T]()
                release[T](this.cleanup, move previous)
                values[idx] = move item
                ret
            elif states[idx] == 2 && firstDeleted == this.capacity:
                firstDeleted = idx
            elif states[idx] == 0:
                if firstDeleted != this.capacity:
                    idx = firstDeleted
                ..
                ownedKey str = try strings.copy(key)
                keys[idx] = move ownedKey
                values[idx] = move item
                states[idx] = 1
                this.length = nextLength
                ret
            ..
        ..
        if firstDeleted != this.capacity:
            fallbackKey str = try strings.copy(key)
            keys[firstDeleted] = move fallbackKey
            values[firstDeleted] = move item
            states[firstDeleted] = 1
            this.length = nextLength
            ret
        ..
        throw errors.wouldOverflow("hash map is full")
    ..
..

HashMap[T].setBorrowed(key str, item T) !void:
    unsafe:
        this.set(key, move item)
    ..
..

# Removes key and releases its value through the configured cleanup callback.
# @throws outOfBounds if key is absent
# @complexity O(1) average, O(N) worst case
# @example
#   try users.delete("alice")
HashMap[T].delete(key str) !void:
    value := try this.take(key)
    release[T](this.cleanup, move value)
..

# Removes key and transfers its value to the caller without invoking cleanup.
# @throws outOfBounds if key is absent
# @ownership The caller becomes responsible for the returned value.
# @complexity O(1) average, O(N) worst case
# @example
#   user := try users.take("alice")
HashMap[T].take(key str) !$T:
    idx := try this.indexOf(key)
    # SAFETY: indexOf returns an occupied slot; zeroing the value and marking a
    # tombstone transfers its unique ownership to the caller exactly once.
    unsafe:
        keys str* = keysPtr[T](this)
        values T* = valuesPtr[T](this)
        states u8* = statesPtr[T](this)
        taken $T = values[idx]
        values[idx] = memory.zeroValue[T]()
        keys[idx].free()
        states[idx] = 2
        this.length = this.length - 1
        ret move taken
    ..
..

# Returns the number of live entries.
# @complexity O(1)
# @example
#   size := users.count()
HashMap[T].count() u64:
    ret this.length
..

# Releases copied keys, owned values, and map storage.
# @complexity O(C), where C is table capacity
# @ownership Invalidates the map and all values borrowed from it.
# @example
#   users.free()
destr HashMap[T].free() void:
    # SAFETY: states identifies every occupied slot; each owned key/value is
    # released once before the single backing allocation is freed.
    unsafe:
        keys str* = keysPtr[T](this)
        states u8* = statesPtr[T](this)
        for i u64 = 0 to this.capacity:
            if states[i] == 1:
                keys[i].free()
            ..
        ..
        if this.cleanup != none:
            values T* = valuesPtr[T](this)
            for i u64 = 0 to this.capacity:
                if states[i] == 1:
                    this.cleanup(move values[i])
                ..
            ..
        ..
    ..
    this.allocator.free(this.storage)
    this.storage = none
    this.capacity = 0
    this.length = 0
..
