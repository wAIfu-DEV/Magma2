mod heap
# Process-heap allocation and a compatible Allocator interface.
# @ownership Returned memory belongs to the caller until freed or transferred.

use "std:allocator" as a
use "std:errors"    as e
use "std:cast"      as cast
use "std:memory"    as mem

@platform("windows")
use "std:win/heap_impl" as impl_heap

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/heap_impl" as impl_heap

# Returns an allocator object that uses the OS's standard heap allocation methods.
# @complexity O(1)
# @example
#   a := heap.allocator()
pub noctx allocator() a.Allocator:
    ret impl_heap.allocator()
..

# Returns a heap-allocated region of memory of exactly nBytes bytes wide.
# nBytes should be greater than 0.
# @warning the region of memory is owned by the caller, meaning the caller is
# responsible for either deallocating, or explicitly transfering ownership to
# consuming clients.
# @warning returned memory region will be uninitialized, do not rely on assumptions
# as to what may be present inside, it is the caller's responsibility to initialize
# the memory region. If you want the memory region to be zeroed-out, use allocZero()
# @param nBytes how many bytes to allocate
# @returns owned region of memory
# @throws outOfMemory when allocation fails
# @example
#   block := try heap.alloc(64)
#   heap.free(block)
pub alloc(nBytes u64) !$u8*:
    ret try impl_heap.alloc(nBytes)
..

# Returns a heap-allocated region of memory of exactly nBytes bytes wide.
# Returned memory region will be zeroed-out.
# nBytes should be greater than 0.
# @warning the region of memory is owned by the caller, meaning the caller is
# responsible for either deallocating, or explicitly transfering ownership to
# consuming clients.
# @param nBytes how many bytes to allocate
# @returns owned region of memory
# @throws outOfMemory when allocation fails
# @complexity O(N) for zero initialization
# @example
#   block := try heap.allocZero(64)
pub allocZero(nBytes u64) !$u8*:
    ret try impl_heap.allocZero(nBytes)
..

# Returns a heap-allocated region of memory of exactly nBytes bytes wide.
# Bytes pointed to by the "in" pointer will be copied to the new region.
# in should be non-null, and should be the result of an allocation from this
# module's allocator or methods, do not mismatch allocators.
# nBytes should be greater than 0.
# @warning the region of memory is owned by the caller, meaning the caller is
# responsible for either deallocating or explicitly transfering ownership to
# consuming clients.
# @warning returned memory region may have its end uninitialized, do not rely on
# assumptions as to what may be present inside, it is the caller's responsibility
# to initialize the memory region past previous size if nBytes > previous size.
# If you want the memory region to be zeroed-out, use allocZero()
# @param in pointer to already allocated memory region
# @param nBytes how many bytes to allocate
# @returns owned region of memory
# @throws outOfMemory when resizing fails
# @ownership The returned pointer replaces in; do not use the old pointer.
# @example
#   block = try heap.realloc(block, 128)
pub realloc(in ptr, nBytes u64) !$u8*:
    ret try impl_heap.realloc(in, nBytes)
..

# Returns a heap-allocated region of memory of exactly nBytes bytes wide.
# Bytes pointed to by the "in" pointer will be copied to the new region.
# in should be non-null, and should be the result of an allocation from this
# module's allocator or methods, do not mismatch allocators.
# nBytes should be greater than 0.
# @warning the region of memory is owned by the caller, meaning the caller is
# responsible for either deallocating or explicitly transfering ownership to
# consuming clients.
# @param in pointer to already allocated memory region
# @param nBytes how many bytes to allocate
# @returns owned region of memory
# @throws outOfMemory when resizing fails
# @warning prevNbytes must be the actual size of the existing allocation.
# @example
#   block = try heap.reallocZero(block, 128, 64)
pub reallocZero(in ptr, nBytes u64, prevNbytes u64) !$u8*:
    ret try impl_heap.reallocZero(in, nBytes, prevNbytes)
..

# Deallocates a heap-allocated region of memory.
# in should be non-null, and should be the result of an allocation from this
# module's allocator or methods, do not mismatch allocators.
# @param in pointer to already allocated memory region
# @complexity O(1), excluding platform allocator cost
# @warning in must be an active allocation returned by this heap.
# @example
#   heap.free(block)
pub free(in ptr) void:
    impl_heap.free(in)
..
