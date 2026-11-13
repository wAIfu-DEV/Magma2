mod list
# Allocator-backed growable lists that retain their allocator for mutation.

# Array differs from List in the way it handles allocators
# Array does not keep an allocator while List does,
# This means List will always have a larger memory footprint than array.
# Prefer using Array instead of List if you make use of composition

use "std:allocator" as alc
use "std:array"     as arr
use "std:iterator"  as iter

# Growable owning sequence that retains its allocator for convenient mutation.
pub List[T](
    allocator alc.Allocator
    array     arr.Array[T]
    cleanup fn($T) void
)

# Creates an empty list with an optional element cleanup callback.
# @complexity O(1), excluding allocation
# @example
#   values := try list.new[Value](a, freeValue)
pub new[T](a alc.Allocator, cleanup fn($T) void) !$List[T]:
	ret List[T](
        allocator=a,
		array=try arr.new[T](a),
        cleanup=cleanup,
    )
..

# Transfers an existing Array into a List using the allocator that created it.
# @ownership Consumes array; the returned list must be freed with a.
# @complexity O(1)
# @example
#   values := list.fromArray[Value](a, backing, freeValue)
pub fromArray[T](a alc.Allocator, array $arr.Array[T], cleanup fn($T) void) $List[T]:
	ret List[T](allocator=a, array=move array, cleanup=cleanup)
..

# Returns the number of elements.
# @complexity O(1)
# @example
#   length := values.count()
List[T].count() u64:
    ret this.array.count()
..

# Removes and cleans up all elements, releasing excess storage.
# @complexity O(N)
# @example
#   try values.clearShrink()
List[T].clearShrink() !void:
    try this.array.clearShrink(this.allocator, this.cleanup)
..

# Removes and cleans up all elements while retaining allocated capacity.
# @complexity O(N)
# @example
#   try values.clearKeep()
List[T].clearKeep() !void:
    try this.array.clearKeep(this.allocator, this.cleanup)
..

# Reallocates storage for usable elements plus spare slots on both sides.
# @warning Shrinking cleans up elements outside the new usable range.
# @complexity O(N)
# @example
#   try values.resize(10, 2, 2)
List[T].resize(usable u64, padLeft u64, padRight u64) !void:
    try this.array.resize(this.allocator, usable, padLeft, padRight, this.cleanup)
..

# Returns a slice of the list's managed items.
# @warning any pop, push, expand operations will lead to the slice pointing to
# now invalid data. Always treat this slice as highly volatile, prefer calling
# .view() multiple times rather than caching its result.
# @complexity O(1)
# @example
#   current := values.view()
List[T].view() T[]:
    ret this.array.view()
..

# Returns the element at index without removing it.
# @complexity O(1)
# @example
#   value := try values.get(0)
List[T].get(index u64) !T:
    ret try this.array.get(index)
..

# Removes the element at index and transfers it to the caller.
# @complexity O(N) when later elements must shift
# @example
#   value := try values.take(0)
List[T].take(index u64) !$T:
    ret try this.array.take(index)
..

# Replaces an element and transfers the previous value to the caller.
# @ownership Consumes value and returns ownership of the displaced element.
# @complexity O(1)
List[T].replace(index u64, value $T) !$T:
    ret try this.array.replace(index, move value)
..

# Replaces an element and cleans up the previous value.
# @ownership Consumes value.
# @complexity O(1)
# @example
#   try values.set(0, replacement)
List[T].set(index u64, value $T) !void:
    ret try this.array.set(this.allocator, index, move value, this.cleanup)
..

# Adds one uninitialized slot at the right and returns its index.
# @complexity O(1) amortized, O(N) when storage grows
# @example
#   index := try values.expandRight()
List[T].expandRight() !u64:
    ret try this.array.expandRight(this.allocator)
..

# Adds one uninitialized slot at the left, shifting existing elements.
# @complexity O(N)
# @example
#   try values.expandLeft()
List[T].expandLeft() !void:
    ret try this.array.expandLeft(this.allocator)
..

# Removes and returns the last element without invoking cleanup.
# @complexity O(1) amortized
# @example
#   last := try values.popRight()
List[T].popRight() !$T:
    ret try this.array.popRight(this.allocator)
..

# Removes and returns the first element without invoking cleanup.
# @complexity O(N)
# @example
#   first := try values.popLeft()
List[T].popLeft() !$T:
    ret try this.array.popLeft(this.allocator)
..

# Appends item and transfers ownership into the list.
# @complexity O(1) amortized
# @example
#   try values.pushRight(item)
List[T].pushRight(item $T) !void:
    try this.array.pushRight(this.allocator, move item)
..

# Prepends item and transfers ownership into the list.
# @complexity O(N)
# @example
#   try values.pushLeft(item)
List[T].pushLeft(item $T) !void:
    try this.array.pushLeft(this.allocator, move item)
..

# Cleans up every element and releases backing storage.
# @complexity O(N)
# @example
#   values.free()
destr List[T].free() void:
    # SAFETY: the List destructor exclusively consumes its embedded Array.
    unsafe:
        this.array.free(this.allocator, this.cleanup)
    ..
..

# Returns a forward iterator borrowing the list's current storage.
# @warning Mutating the list invalidates the iterator.
# @complexity O(1)
# @example
#   it := values.iterator()
List[T].iterator() iter.Iterator[T]:
    ret this.array.iterator()
..
