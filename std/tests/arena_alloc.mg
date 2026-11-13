mod main

use "std:arena_alloc" as arena_alloc
use "std:errors" as errors
use "std:heap" as heap

pub main() !void:
    arena := try arena_alloc.new(1024)
    defer arena.destroy()
    a := arena.allocator()

    first := try a.alloc(32)
    # SAFETY: alloc returned a writable 32-byte allocation.
    unsafe:
        first[0] = 41
    ..
    first = try a.realloc(first, 64)
    # SAFETY: successful realloc returned 64 bytes and preserves the prefix.
    unsafe:
        if first[0] != 41 || arena.used() == 0:
            throw errors.failure("arena realloc did not preserve data")
        ..
    ..

    a.free(first)
    arena.reset()
    if arena.used() != 0:
        throw errors.failure("arena reset did not release allocations")
    ..

    second := try a.alloc(32)
    if second == none:
        throw errors.failure("arena allocation after reset failed")
    ..
..
