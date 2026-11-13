mod heap
# Deterministic allocator used to exercise allocation-failure handling.
# @warning Intended for testing rather than production allocation.

use "std:allocator" as a
use "std:errors"    as e
use "std:cast"      as cast

# Internals for alloc, used by both alloc() and HeapAllocator.alloc()
# @complexity O(1) for allocation itself, O(N) for zeroing if requested.
fakeAlloc(impl ptr, nBytes u64) !$u8*:
    throw e.failure("fake alloc")
    ret none
..

# Internals for realloc, used by both realloc() and HeapAllocator.realloc()
# @complexity O(1) for reallocation itself.
fakeRealloc(impl ptr, in u8*, nBytes u64) !$u8*:
    throw e.failure("fake realloc")
    ret none
..

# Internals for free, used by both free() and HeapAllocator.free()
# @complexity O(1).
fakeFree(impl ptr, in u8*) void:
    ret
..

FakeAllocator impl a.Allocator(value u8)

FakeAllocator.alloc(nBytes u64) !$u8*:
    ret try fakeAlloc(none, nBytes)
..

FakeAllocator.realloc(in ptr, nBytes u64) !$u8*:
    ret try fakeRealloc(none, cast.reinterpret[u8](in), nBytes)
..

FakeAllocator.free(in ptr) void:
    fakeFree(none, cast.reinterpret[u8](in))
..

gl_fakeAllocator := FakeAllocator(value=0)

# Returns an allocator whose allocation and reallocation operations always fail.
# Free is accepted as a no-op, allowing failure-path tests to use normal cleanup.
# @complexity O(1).
# @returns non-owning deterministic failure allocator
# @example
#   a := fake_alloc.allocator()
#   block u8*, allocationError error = a.alloc(16)
pub allocator() a.Allocator:
    ret gl_fakeAllocator.protoBorrow()
..
