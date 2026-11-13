mod heap_impl_unix
# Unix process-heap backend used by the portable heap module.


use "std:c" as c
use "std:allocator" as a
use "std:errors"    as e
use "std:cast"      as cast
use "std:memory"    as mem

ext ext_stdlib_malloc  malloc(size c.size_t) ptr
ext ext_stdlib_realloc realloc(block ptr, newSize c.size_t) ptr
ext ext_stdlib_free    free(block ptr) void

# Internals for alloc, used by both alloc() and HeapAllocator.alloc()
heapAlloc(impl ptr, nBytes u64) !$u8*:
    if nBytes == 0:
        throw e.invalidArgument("requested size is 0")
    ..
    p ptr = ext_stdlib_malloc(nBytes)

    if p == none:
        throw e.outOfMemory("OOM")
    ..
    # SAFETY: malloc returned a validated non-null allocation of nBytes bytes.
    unsafe:
        ret cast.reinterpret[u8](p)
    ..
..

# Internals for realloc, used by both realloc() and HeapAllocator.realloc()
heapRealloc(impl ptr, in ptr, nBytes u64) !$u8*:
    if in == none:
        throw e.invalidArgument("input pointer is null")
    ..
    if nBytes == 0:
        throw e.invalidArgument("requested size is 0")
    ..
    p ptr = ext_stdlib_realloc(in, nBytes)

    if p == none:
        throw e.outOfMemory("OOM")
    ..
    # SAFETY: realloc returned a validated non-null replacement allocation.
    unsafe:
        ret cast.reinterpret[u8](p)
    ..
..

# Internals for free, used by both free() and HeapAllocator.free()
heapFree(impl ptr, in ptr) void:
    if in == none:
        ret
    ..
    ext_stdlib_free(in)
..

HeapAllocator impl a.Allocator(value u8)

HeapAllocator.alloc(nBytes u64) !$u8*:
    ret try heapAlloc(none, nBytes)
..

HeapAllocator.realloc(in ptr, nBytes u64) !$u8*:
    ret try heapRealloc(none, in, nBytes)
..

HeapAllocator.free(in ptr) void:
    heapFree(none, in)
..

gl_heapAllocator := HeapAllocator(value=0)

# Returns an allocator object that uses the OS's standard heap allocation methods.
pub noctx allocator() a.Allocator:
    ret gl_heapAllocator.protoBorrow()
..

# Returns a heap-allocated region of memory of exactly nBytes bytes wide.
# nBytes should be greater than 0.
# Warning: the region of memory is owned by the caller, meaning the caller is
# responsible for either deallocating, or explicitly transfering ownership to
# consuming clients.
# Warning: returned memory region will be uninitialized, do not rely on assumptions
# as to what may be present inside, it is the caller's responsibility to initialize
# the memory region. If you want the memory region to be zeroed-out, use allocZero()
# @param nBytes how many bytes to allocate
# @returns owned region of memory
pub alloc(nBytes u64) !$u8*:
    ret try heapAlloc(none, nBytes)
..

# Returns a heap-allocated region of memory of exactly nBytes bytes wide.
# Returned memory region will be zeroed-out.
# nBytes should be greater than 0.
# Warning: the region of memory is owned by the caller, meaning the caller is
# responsible for either deallocating, or explicitly transfering ownership to
# consuming clients.
# @param nBytes how many bytes to allocate
# @returns owned region of memory
pub allocZero(nBytes u64) !$u8*:
    out u8* = try heapAlloc(none, nBytes)
    mem.zero(out, nBytes)
    ret out
..

# Returns a heap-allocated region of memory of exactly nBytes bytes wide.
# Bytes pointed to by the "in" pointer will be copied to the new region.
# in should be non-null, and should be the result of an allocation from this
# module's allocator or methods, do not mismatch allocators.
# nBytes should be greater than 0.
# Warning: the region of memory is owned by the caller, meaning the caller is
# responsible for either deallocating or explicitly transfering ownership to
# consuming clients.
# Warning: returned memory region may have its end uninitialized, do not rely on
# assumptions as to what may be present inside, it is the caller's responsibility
# to initialize the memory region past previous size if nBytes > previous size.
# If you want the memory region to be zeroed-out, use allocZero()
# @param in pointer to already allocated memory region
# @param nBytes how many bytes to allocate
# @returns owned region of memory
pub realloc(in ptr, nBytes u64) !$u8*:
    ret try heapRealloc(none, in, nBytes)
..

# Returns a heap-allocated region of memory of exactly nBytes bytes wide.
# Bytes pointed to by the "in" pointer will be copied to the new region.
# in should be non-null, and should be the result of an allocation from this
# module's allocator or methods, do not mismatch allocators.
# nBytes should be greater than 0.
# Warning: the region of memory is owned by the caller, meaning the caller is
# responsible for either deallocating or explicitly transfering ownership to
# consuming clients.
# @param in pointer to already allocated memory region
# @param nBytes how many bytes to allocate
# @returns owned region of memory
pub reallocZero(in ptr, nBytes u64, prevNbytes u64) !$u8*:
    if nBytes <= prevNbytes:
        ret try heapRealloc(none, in, nBytes)
    ..
    # manual realloc
    out u8* = try heapAlloc(none, nBytes)
    mem.copy(in, out, prevNbytes)

    # zero end of region
    outEnd ptr = cast.utop(cast.ptou(out) + prevNbytes)
    mem.zero(outEnd, nBytes - prevNbytes)

    heapFree(none, in)
    ret out
..

# Deallocates a heap-allocated region of memory.
# in should be non-null, and should be the result of an allocation from this
# module's allocator or methods, do not mismatch allocators.
# @param in pointer to already allocated memory region
pub free(in ptr) void:
    heapFree(none, in)
..
