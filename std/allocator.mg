mod allocator
# Allocator interfaces for allocating, resizing, and releasing owned memory.
# Allocations must be released through the same allocator that created them.

use "std:errors" as errors
use "std:checked" as checked
use "std:cast" as cast
use "std:llvm" as low

# Generic allocator interface backed by a compiler-generated immutable vtable.
pub proto Allocator(
    alloc(byteCount u64) !$u8*
    realloc(block ptr, byteCount u64) !$u8*
    free(block ptr) void
)

# Allocates a new block of size count * sizeof T.
# @complexity O(1) wrapper call; allocator-dependent.
# @param count number of T elements to allocate
# @returns owned memory block
# @throws outOfMemory when the allocator cannot satisfy the request
# @ownership Release the block with the same allocator.
# @example
#   values := try a.allocT[u64](16)
#   a.free(values)
Allocator.allocT[T](count u64) !$T*:
    ret cast.reinterpret[T](try this.alloc(try checked.byteCount[T](count)))
..

# Reallocates a block of size count * sizeof T.
# @complexity O(1) wrapper call; allocator-dependent.
# @param block existing allocation
# @param count new number of T elements
# @returns owned memory block
# @throws outOfMemory when the block cannot be resized
# @ownership The returned pointer replaces block and remains owned by the caller.
Allocator.reallocT[T](block T*, count u64) !$T*:
    ret cast.reinterpret[T](try this.realloc(block, try checked.byteCount[T](count)))
..

# Zero vtable marks an inactive allocator in borrowed string descriptors.
pub noctx empty() Allocator:
    value Allocator
    ret value
..

# The first two machine words of a borrowed Allocator are its wrapper vtable
# and the implementation pointer kept in inline proto storage. Strings retain
# those two words and reconstruct a borrowed proto when releasing their data.
# The implementation must stay alive until every string using it is released.
AllocatorBorrowedHeader(
    vtable ptr
    implementation ptr
)

AllocatorEmbeddedFields(
    implementation ptr
    vtable ptr
)

pub noctx fromEmbedded(p ptr) Allocator:
    unsafe:
        fields AllocatorEmbeddedFields* = low.reinterpret[AllocatorEmbeddedFields](p)
        value Allocator
        value.vtable = fields.vtable
        raw AllocatorBorrowedHeader* = low.reinterpret[AllocatorBorrowedHeader](addrof value)
        raw.implementation = fields.implementation
        ret value
    ..
..

pub noctx Allocator.implementation() ptr:
    unsafe:
        raw AllocatorBorrowedHeader* = low.reinterpret[AllocatorBorrowedHeader](this)
        ret raw.implementation
    ..
..

pub noctx Allocator.dispatchTable() ptr:
    ret this.vtable
..

# Reports whether this protocol has no dispatch table. Such a value cannot
# allocate or free and is used as the non-owning marker in intrinsic strings.
pub noctx Allocator.isNull() bool:
    ret this.vtable == none
..

# Stable placeholder used by containers whose optional backing allocator is
# inactive (for example arenas over caller-owned buffers).
NullAllocator impl Allocator(
    value u8
)

NullAllocator.alloc(byteCount u64) !$u8*:
    throw errors.invalidArgument("null allocator cannot allocate")
    ret none
..

NullAllocator.realloc(block ptr, byteCount u64) !$u8*:
    throw errors.invalidArgument("null allocator cannot reallocate")
    ret none
..

NullAllocator.free(block ptr) void:
..

gl_nullAllocator := NullAllocator(value=0)

pub noctx null() Allocator:
    ret gl_nullAllocator.protoBorrow()
..
