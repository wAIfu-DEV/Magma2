mod heap_impl_win
# Windows process-heap backend used by the portable heap module.


use "std:win/types" as win
use "std:allocator" as a
use "std:errors"    as e
use "std:cast"      as cast
use "std:memory"    as mem
use "std:llvm"      as ll
# Windows heap API
ext ext_win32_GetProcessHeap GetProcessHeap() win.HANDLE
ext ext_win32_HeapAlloc      HeapAlloc(hHeap win.HANDLE, dwFlags win.DWORD, dwBytes win.SIZE_T) win.LPVOID
ext ext_win32_HeapReAlloc    HeapReAlloc(hHeap win.HANDLE, dwFlags win.DWORD, lpMem win.LPVOID, dwBytes win.SIZE_T) win.LPVOID
ext ext_win32_HeapFree       HeapFree(hHeap win.HANDLE, dwFlags win.DWORD, lpMem win.LPVOID) win.BOOL

# The process heap is immutable and cached process-wide.
global processHeap ptr

loadHeap() ptr:
    ret ll.atomicLoadAcquirePtr(addrof processHeap)
..

publishHeap(value ptr) void:
    ll.atomicStoreReleasePtr(addrof processHeap, value)
..

# Gets the process heap handle, cached for performance
# O(1) after first call.
getHeap() ptr:
    heap := loadHeap()
    if heap == none:
        heap = ext_win32_GetProcessHeap()
        if heap != none: publishHeap(heap) ..
    ..
    ret heap
..

# Internals for alloc, used by both alloc() and HeapAllocator.alloc()
# O(1) for allocation itself, O(N) for zeroing if requested.
heapAlloc(impl ptr, nBytes u64) !$u8*:
    if nBytes == 0:
        throw e.invalidArgument("requested size is 0")
    ..

    heap ptr = getHeap()
    p ptr = ext_win32_HeapAlloc(heap, 0, nBytes)

    if p == none:
        throw e.outOfMemory("OOM")
    ..
    ret cast.reinterpret[u8](p)
..

# Internals for realloc, used by both realloc() and HeapAllocator.realloc()
# O(1) for reallocation itself.
heapRealloc(impl ptr, in ptr, nBytes u64) !$u8*:
    if in == none:
        throw e.invalidArgument("input pointer is null")
    ..

    if nBytes == 0:
        throw e.invalidArgument("requested size is 0")
    ..

    heap ptr = getHeap()
    p ptr = ext_win32_HeapReAlloc(heap, 0, in, nBytes)

    if p == none:
        throw e.outOfMemory("OOM")
    ..
    ret cast.reinterpret[u8](p)
..

# Internals for free, used by both free() and HeapAllocator.free()
# O(1).
heapFree(impl ptr, in ptr) void:
    if in == none:
        ret
    ..

    heap ptr = getHeap()
    ok win.BOOL = ext_win32_HeapFree(heap, 0, in)
    if ok == 0:
        ret
    ..
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

# Returns an allocator object that uses Windows heap allocation.
# O(1).
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
    unsafe:
        mem.zero(out, nBytes)
    ..
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
# @param prevNbytes previous size of the allocation
# @returns owned region of memory
pub reallocZero(in ptr, nBytes u64, prevNbytes u64) !$u8*:
    if nBytes <= prevNbytes:
        ret try heapRealloc(none, in, nBytes)
    ..
    # manual realloc
    out u8* = try heapAlloc(none, nBytes)
    unsafe:
        mem.copy(in, out, prevNbytes)
    ..

    # zero end of region
    outEnd ptr
    unsafe:
        outEnd = cast.utop(cast.ptou(out) + prevNbytes)
    ..
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
