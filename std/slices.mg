mod slices
# Low-level slice construction, allocation, reinterpretation, and release.

use "std:allocator" as alc
use "std:cast"      as cast
use "std:checked"   as checked
use "std:errors"    as err

# Returns element count of slice.
# @complexity O(1).
# @param s input slice
# @returns element count
# @example
#   length := slices.count(values)
pub count(s slice) u64:
    ret s.__count
..

# Creates a slice from a pointer and element count.
# @complexity O(1).
# @param p pointer to first element
# @param elemCount number of elements
# @returns slice view
# @safety p must reference at least elemCount valid elements.
# @example
#   view := slices.fromPtr(pointer, 16)
pub fromPtr(p ptr, elemCount u64) slice:
    ret slice(__data=p, __count=elemCount)
..

# Reinterprets a slice's backing memory as elements of another type.
# The result length is rounded down if the byte size is not divisible by sizeof R.
# @complexity O(1)
# @param in source slice
# @returns non-owning view over the same backing memory
# @throws wouldOverflow if the source byte size cannot be represented
# @safety The backing memory must satisfy R's alignment and representation requirements.
# @example
#   words := slices.reinterpret[u8, u32](bytes)
pub reinterpret[T, R](in T[]) !R[]:
    byteSize u64 = try checked.byteCount[T](count(in))
    newSize u64 = byteSize / sizeof R
    ret fromPtr(toPtr(in), newSize)
..

# Returns the underlying data pointer of a slice.
# @complexity O(1).
# @param s input slice
# @returns data pointer
# @example
#   pointer := slices.toPtr(values)
pub toPtr(s slice) ptr:
    ret s.__data
..

# Returns a borrowed half-open subrange while preserving the source lifetime.
# The raw descriptor construction remains localized in fromPtr.
# @complexity O(1)
# @throws outOfBounds when start > end or end exceeds the source count
pub subslice[T](in T[], start u64, end u64) !T[]:
    sourceCount u64 = count(in)
    if start > end || end > sourceCount:
        throw err.outOfBounds("subslice bounds are invalid")
    ..
    offset u64 = try checked.byteCount[T](start)
    data ptr = cast.utop(cast.ptou(toPtr(in)) + offset)
    ret fromPtr(data, end - start)
..

# Allocates an owned, uninitialized slice of T values.
# @complexity O(1), excluding allocator cost
# @param a allocator used for the backing memory
# @param elemCount number of elements to allocate
# @returns owned slice with elemCount elements
# @throws outOfMemory when allocation fails
# @ownership Release the result with free using the same allocator.
# @example
#   values := try slices.alloc[u64](16)
#   slices.free(values)
pub alloc[T](elemCount u64) !$T[]:
    a := ctx.alloc
    p T* = try a.allocT[T](elemCount)
    ret fromPtr(p, elemCount)
..

# Releases the backing memory of an owned slice.
# @complexity O(1), excluding allocator cost
# @param a allocator that originally allocated the slice
# @param s owned slice to release
# @warning Passing a borrowed slice or a different allocator is invalid.
# @ownership Consumes the slice and releases its allocation.
# @example
#   slices.free(values)
pub free(s slice) void:
    a := ctx.alloc
    p ptr = toPtr(s)
    a.free(p)
..
