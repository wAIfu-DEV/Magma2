mod array
# Growable contiguous arrays with explicit allocator and ownership control.

# Array differs from List in the way it handles allocators
# Array does not keep an allocator while List does.
# Prefer using Array instead of List if you make use of composition

use "std:allocator" as alc
use "std:slices"    as slc
use "std:cast"      as cast
use "std:errors"    as err
use "std:memory"    as mem
use "std:iterator"  as iter
use "std:footgun"   as fg
use "std:checked"   as checked

# Padding is biased for append-first workloads
const DEFAULT_PAD_LEFT u64 = 2
const DEFAULT_PAD_RIGHT u64 = 4
const DEFAULT_CAPACITY u64 = 6

State(
    capacity u64
    size u64
    leftOffset u64
    # Keep the element region 16-byte aligned for values such as u128.
    reserved u64
)

State.rightBufferSize() u64:
    ret this.capacity - (this.size + this.leftOffset)
..

# Growable contiguous storage with optional padding at either end.
# Array does not retain its allocator; pass the same allocator to every operation.
pub Array[T](
    data T*,
    state State*,
)

byteSize[T](count u64) !u64:
    ret try checked.byteCount[T](count)
..

addSize(a u64, b u64) !u64:
    ret try checked.uAdd(a, b)
..

growCapacity(capacity u64) !u64:
    expanded u64 = try addSize(capacity, capacity / 2)
    ret try addSize(expanded, capacity / 4)
..

# Creates an empty array with default growth padding.
# @complexity O(1), excluding allocator cost
# @param a allocator used for initial storage
# @returns owned empty array
# @ownership Release with Array.free using the same allocator.
# @example
#   values := try array.new[u64](a)
#   try values.pushRight(a, 42)
pub new[T](a alc.Allocator) !$Array[T]:
    ret try newWithSize[T](a, 0, DEFAULT_PAD_LEFT, DEFAULT_PAD_RIGHT)
..

# Creates a zero-initialized array with explicit usable size and growth padding.
# @complexity O(usable + padLeft + padRight)
# @param a allocator used for storage
# @param usable number of initially accessible elements
# @param padLeft reserved elements before the accessible range
# @param padRight reserved elements after the accessible range
# @returns owned array
# @ownership Release with Array.free using the same allocator.
# @example
#   values := try array.newWithSize[u64](a, 8, 0, 8)
pub newWithSize[T](a alc.Allocator, usable u64, padLeft u64, padRight u64) !$Array[T]:
    if padLeft < DEFAULT_PAD_LEFT:
        padLeft = DEFAULT_PAD_LEFT
    ..
    if padRight < DEFAULT_PAD_RIGHT:
        padRight = DEFAULT_PAD_RIGHT
    ..
    capacity u64 = try addSize(usable, padLeft)
    capacity = try addSize(capacity, padRight)
    dataSize u64 = try byteSize[T](capacity)

    stateSize u64 = sizeof State
    allocationSize u64 = try addSize(stateSize, dataSize)
    headAndData u8* = try a.alloc(allocationSize)
    data u8* = none
    # SAFETY: the checked allocation size includes the aligned State header.
    unsafe:
        data = cast.utop(cast.ptou(headAndData) + stateSize)
    ..

    # All elements exposed by usable must have a defined value. Zero the full
    # data region so padding that is later consumed by expand is defined too.
    mem.zero(data, dataSize)

    state State* = none
    # SAFETY: headAndData is a fresh allocation sized for State plus data.
    unsafe:
        state = headAndData
        *state = State(
            capacity = capacity
            size = usable
            leftOffset = padLeft
            reserved = 0
        )
    ..

    # SAFETY: the returned owner records both views of the same fresh allocation.
    unsafe:
        ret Array[T](
            data = data
            state = state
        )
    ..
..

# Returns the number of accessible values.
# @complexity O(1)
# @example
#   length := values.count()
Array[T].count() u64:
    ret this.state.size
..

runCleanupFromIdx[T](arr Array[T]*, idx u64, cleanup fn($T) void) void:
    if cleanup != none:
        items := arr.view()
        i u64 = idx
        valSize u64 = sizeof T
        loop i < items.count():
            # SAFETY: this is the container's occupancy-aware removal path.
            unsafe:
                if mem.isZero(addrof items[i], valSize) == false:
                    value $T = items[i]
                    items[i] = mem.zeroValue[T]()
                    cleanup(move value)
                ..
            ..
            i = i + 1
        ..
    ..
..

runCleanup[T](arr Array[T]*, cleanup fn($T) void) void:
    runCleanupFromIdx[T](arr, 0, cleanup)
..

# Removes every value and shrinks storage back to the default padding.
# @complexity O(N), plus cleanup cost
# @param a allocator originally used by the array
# @param cleanup callback for removed values, or none
# @example
#   try values.clearShrink(a, none)
Array[T].clearShrink(a alc.Allocator, cleanup fn($T) void) !void:
    oldState := this.state

    tmp := try new[T](a)

    # Allocate first so failure leaves both the Array and its elements owned.
    runCleanup[T](this, cleanup)

    a.free(oldState)
    # SAFETY: this is the checked whole-container replacement path.
    unsafe:
        *this = move tmp
    ..
..

# Removes every value while retaining the current allocation for reuse.
# @complexity O(N), plus cleanup cost
# @param a allocator originally used by the array
# @param cleanup callback for removed values, or none
# @example
#   try values.clearKeep(a, none)
Array[T].clearKeep(a alc.Allocator, cleanup fn($T) void) !void:
    if this.state.capacity < DEFAULT_CAPACITY:
        # This will reset to default size
        try this.clearShrink(a, cleanup)
        ret
    ..

    runCleanup[T](this, cleanup)

    # This will bias storage keeping to the end of the array and not the front,
    # this is good for append workloads but not so much prepend.
    # Since prepend is usually rarer than append, this seems like a sensible default.
    this.state.size = 0
    this.state.leftOffset = DEFAULT_PAD_LEFT
..

resizeStorage[T](array Array[T]*, a alc.Allocator, usable u64, padLeft u64, padRight u64, cleanup fn($T) void) !void:
    newCont u64 = try addSize(usable, padLeft)
    newCont = try addSize(newCont, padRight)

    newSize u64 = try byteSize[T](newCont)

    stateSize u64 = sizeof State
    tSize u64 = sizeof T

    allocationSize u64 = try addSize(stateSize, newSize)
    newHeadAndData u8* = try a.alloc(allocationSize)
    newData ptr = cast.utop(cast.ptou(newHeadAndData) + stateSize)

    reg0 u64 = cast.ptou(array.data) + (array.state.leftOffset * tSize)
    reg1 u64 = cast.ptou(newData) + (padLeft * tSize)
    
    count u64 = array.count()
    if usable < count:
        count = usable
        runCleanupFromIdx[T](array, usable, cleanup)
    ..
    nBytes u64 = count * tSize

    mem.copy(cast.utop(reg0), cast.utop(reg1), nBytes)
    
    a.free(array.state)

    # SAFETY: both pointers refer into the fresh checked allocation.
    unsafe:
        array.data = newData
        array.state = newHeadAndData
    ..

    # SAFETY: array.state points at the newly allocated State header.
    unsafe:
        *array.state = State(
            capacity = newCont,
            size = usable,
            leftOffset = padLeft
            reserved = 0
        )
    ..
..

# Resizes the accessible range and replaces both growth-padding regions.
# Removed values are passed to cleanup; new values are zero-initialized.
# @param a allocator originally used by the array
# @param usable requested accessible element count
# @param padLeft requested reserved capacity before the accessible range
# @param padRight requested reserved capacity after the accessible range
# @param cleanup callback for values removed by shrinking, or none
# @complexity O(N), where N is the number of values copied or cleaned up
Array[T].resize(a alc.Allocator, usable u64, padLeft u64, padRight u64, cleanup fn($T) void) !void:
    oldCount u64 = this.count()
    try resizeStorage[T](this, a, usable, padLeft, padRight, cleanup)

    if usable > oldCount:
        items := this.view()
        firstNew ptr = cast.utop(cast.ptou(slc.toPtr(items)) + (oldCount * sizeof T))
        newCount u64 = usable - oldCount
        newBytes u64 = try byteSize[T](newCount)
        mem.zero(firstNew, newBytes)
    ..
..

# Returns a slice of the list's managed items.
# This generally leads to faster read / write operations than using get / set
# @warning Overwriting a slot from the view will lead to no destructor being called on the value.
# @warning any pop, push, expand operations will lead to the slice pointing to
# now invalid data. Always treat this slice as highly volatile, prefer calling
# .view() multiple times rather than caching its result.
# @complexity O(1)
# @example
#   items := values.view()
#   first := items[0]
Array[T].view() T[]:
    ret slc.fromPtr(cast.utop(cast.ptou(this.data) + (this.state.leftOffset * sizeof T)), this.state.size)
..

# Returns a borrowed copy of the value at index.
# @complexity O(1)
# @throws outOfBounds when index is outside the accessible range
# @example
#   value := try values.get(0)
Array[T].get(index u64) !T:
    if index >= this.state.size:
        throw err.outOfBounds("index is out of bounds")
    ..

    # SAFETY: state bounds and the allocation layout prove this element exists.
    unsafe:
        idx u64 = this.state.leftOffset + index
        typedPtr T* = cast.reinterpret[T](this.data)
        ret typedPtr[idx]
    ..
..

# Removes and returns ownership of the value at index without changing array length.
# The vacated slot is replaced with T's zero value.
# @throws outOfBounds when index is outside the accessible range
# @complexity O(1)
Array[T].take(index u64) !$T:
    if index >= this.state.size:
        throw err.outOfBounds("index is out of bounds")
    ..

    # SAFETY: this is the container's occupancy-aware extraction path.
    unsafe:
        idx u64 = this.state.leftOffset + index
        typedPtr T* = cast.reinterpret[T](this.data)
        val $T = typedPtr[idx]
        typedPtr[idx] = mem.zeroValue[T]()
        ret move val
    ..
..

# Replaces an element and transfers the previous value to the caller.
# Both ownership transfers are explicit; no cleanup callback is invoked.
# @throws outOfBounds when index is outside the accessible range
# @complexity O(1)
Array[T].replace(index u64, value $T) !$T:
    onerror fg.drop[T](move value)
    if index >= this.state.size:
        throw err.outOfBounds("index is out of bounds")
    ..

    # SAFETY: this is the container's occupancy-aware replacement path.
    unsafe:
        idx u64 = this.state.leftOffset + index
        typedPtr T* = cast.reinterpret[T](this.data)
        previous $T = typedPtr[idx]
        typedPtr[idx] = move value
        ret move previous
    ..
..

# Replaces the value at index, optionally cleaning up the previous value.
# @param index destination index
# @param value owned replacement value
# @param cleanup callback for the overwritten value, or none
# @throws outOfBounds when index is outside the accessible range
# @complexity O(1), plus cleanup cost
Array[T].set(a alc.Allocator, index u64, value $T, cleanup fn($T) void) !void:
    onerror:
        if cleanup != none:
            cleanup(move value)
        else:
            fg.drop[T](move value)
        ..
    ..
    if index >= this.state.size:
        throw err.outOfBounds("index is out of bounds")
    ..

    # SAFETY: this is the container's checked cleanup-and-replacement path.
    unsafe:
        idx u64 = this.state.leftOffset + index
        typedPtr T* = cast.reinterpret[T](this.data)
        if cleanup != none:
            previous $T = typedPtr[idx]
            typedPtr[idx] = mem.zeroValue[T]()
            cleanup(move previous)
        ..
        typedPtr[idx] = move value
        ret
    ..
..

expandRightStorage[T](array Array[T]*, a alc.Allocator) !u64:
    state := array.state
    if state.rightBufferSize() > 0:
        state.size = state.size + 1
        ret array.count() - 1
    ..
    # If no more space in back buffer, expand rightwards

    oldCont u64 = array.state.capacity
    expanded u64 = try growCapacity(oldCont) # 1.75 factor

    expandedSize u64 = try byteSize[T](expanded)
    stateSize u64 = sizeof State

    allocationSize u64 = try addSize(stateSize, expandedSize)
    # SAFETY: realloc preserves the State-header-plus-elements allocation layout.
    unsafe:
        array.state = try a.realloc(array.state, allocationSize)
    ..
    # SAFETY: state is followed by the aligned element region in this allocation.
    unsafe:
        array.data = cast.utop(cast.ptou(array.state) + stateSize)
    ..
    array.state.capacity = expanded
    array.state.size = array.state.size + 1
    
    ret array.count() - 1
..

# Appends a zero-initialized slot and returns its index.
# @complexity Amortized O(1); O(N) when storage grows
Array[T].expandRight(a alc.Allocator) !u64:
    idx u64 = try expandRightStorage[T](this, a)
    items := this.view()
    bounded idx < items.count():
        mem.zero(addrof items[idx], sizeof T)
    ..
    ret idx
..

expandLeftStorage[T](array Array[T]*, a alc.Allocator) !void:
    state := array.state
    if state.leftOffset > 0:
        state.leftOffset = state.leftOffset - 1
        state.size = state.size + 1
        ret
    ..
    oldCont u64 = array.state.capacity
    expanded u64 = try growCapacity(oldCont) # 1.75 factor
    newPad u64 = expanded - oldCont

    try resizeStorage[T](array, a, array.state.size, newPad, array.state.rightBufferSize(), none)
    array.state.leftOffset = array.state.leftOffset - 1
    array.state.size = array.state.size + 1
..

# Prepends a zero-initialized slot.
# @complexity Amortized O(1); O(N) when storage grows
Array[T].expandLeft(a alc.Allocator) !void:
    try expandLeftStorage[T](this, a)
    items := this.view()
    bounded 0 < items.count():
        mem.zero(addrof items[0], sizeof T)
    ..
..

# Removes and returns ownership of the last value.
# @complexity Amortized O(1); O(N) when storage shrinks
# @throws wouldOverflow when the array is empty
Array[T].popRight(a alc.Allocator) !$T:
    if this.state.size == 0:
        throw err.wouldOverflow("cannot pop from empty Array")
    ..

    rightBuffer u64 = this.state.rightBufferSize()
    if rightBuffer > this.state.size && rightBuffer - this.state.size > this.state.size:
        # shrink right padding
        rightPad u64 = this.state.size / 2
        if rightPad < DEFAULT_PAD_RIGHT:
            rightPad = DEFAULT_PAD_RIGHT
        ..
        try resizeStorage[T](this, a, this.state.size, this.state.leftOffset, rightPad, none)
    ..

    items T[] = this.view()
    index u64 = this.state.size - 1
    bounded index < items.count():
        # SAFETY: this is the container's occupancy-aware removal path.
        unsafe:
            item $T = items[index]
            items[index] = mem.zeroValue[T]()

            this.state.size = this.state.size - 1
            ret move item
        ..
    ..

    throw err.outOfBounds("array storage invariant failed")
..

# Removes and returns ownership of the first value.
# @complexity Amortized O(1); O(N) when storage shrinks
# @throws wouldOverflow when the array is empty
Array[T].popLeft(a alc.Allocator) !$T:
    if this.state.size == 0:
        throw err.wouldOverflow("Cannot pop from an empty Array.")
    ..

    if this.state.leftOffset > this.state.size && this.state.leftOffset - this.state.size > this.state.size:
        # shrink right padding
        leftPad u64 = this.state.size / 2
        if leftPad < DEFAULT_PAD_LEFT:
            leftPad = DEFAULT_PAD_LEFT
        ..
        try resizeStorage[T](this, a, this.state.size, leftPad, this.state.rightBufferSize(), none)
    ..

    items T[] = this.view()
    bounded 0 < items.count():
        # SAFETY: this is the container's occupancy-aware removal path.
        unsafe:
            item $T = items[0]
            items[0] = mem.zeroValue[T]()
            this.state.leftOffset = this.state.leftOffset + 1
            this.state.size = this.state.size - 1
            ret move item
        ..
    ..
    throw err.outOfBounds("array storage invariant failed")
..

# Appends an owned value to the array.
# @complexity Amortized O(1); O(N) when storage grows
# @example
#   try values.pushRight(a, 42)
Array[T].pushRight(a alc.Allocator, item $T) !void:
    idx u64 = try expandRightStorage[T](this, a)
    items T[] = this.view()
    bounded idx < items.count():
        # SAFETY: expandRightStorage initialized this vacant slot.
        unsafe:
            items[idx] = move item
        ..
    ..
..

# Prepends an owned value to the array.
# @complexity Amortized O(1); O(N) when storage grows
Array[T].pushLeft(a alc.Allocator, item $T) !void:
    try expandLeftStorage[T](this, a)
    items T[] = this.view()
    bounded 0 < items.count():
        # SAFETY: expandLeftStorage initialized this vacant slot.
        unsafe:
            items[0] = move item
        ..
    ..
..

# Cleans up all remaining values and releases the array storage.
# @param a allocator originally used by the array
# @param cleanup callback for each remaining value, or none
# @complexity O(N), plus cleanup cost
# @example
#   values.free(a, none)
destr Array[T].free(a alc.Allocator, cleanup fn($T) void) void:
    if this.state == none:
        ret
    ..

    runCleanup[T](this, cleanup)

    a.free(this.state)
    this.state = none
    this.data = none
..

iterHasData[T](impl Array[T]*, index u64) bool:
    bound := impl.count()
    ret index < bound
..

iterNext[T](impl Array[T]*, index u64) !T:
    view := impl.view()
    if index >= view.count():
        throw err.outOfBounds("iterator index is out of bounds")
    ..
    ret view[index]
..

# Creates a non-owning iterator over the array's current accessible values.
# @warning Mutating or freeing the array invalidates the iterator.
# @complexity O(1) to create; O(1) per yielded value
Array[T].iterator() iter.Iterator[T]:
    ret iter.new[T](this, iterHasData[T], iterNext[T])
..
