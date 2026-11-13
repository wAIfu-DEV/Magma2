mod main

use "std:scratch_alloc" as scratch_alloc
use "std:errors" as errors
use "std:heap" as heap

pub main() !void:
    scratch := try scratch_alloc.new(1024)
    defer scratch.destroy()
    a := scratch.allocator()

    first := try a.alloc(64)
    second := try a.alloc(64)
    # SAFETY: first names a live writable 64-byte allocation.
    unsafe:
        first[0] = 73
    ..
    a.free(second)
    first = try a.realloc(first, 160)
    # SAFETY: successful realloc returned 160 bytes and preserves the prefix.
    unsafe:
        if first[0] != 73:
            throw errors.failure("scratch realloc did not preserve data")
        ..
    ..

    a.free(first)
    large := try a.alloc(800)
    if large == none:
        throw errors.failure("scratch coalescing failed")
    ..
    a.free(large)
    scratch.reset()
..
