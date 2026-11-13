mod main
use "std:errors" as errors
use "std:heap" as heap
pub main() !void:
    a := heap.allocator()
    viaAllocator := try a.alloc(8)
    a.free(viaAllocator)
    raw := try heap.alloc(8)
    # SAFETY: raw names a live writable 8-byte allocation.
    unsafe:
        raw[0] = 7
    ..
    raw = try heap.realloc(raw, 16)
    # SAFETY: successful realloc returned 16 bytes and preserves the prefix.
    unsafe:
        if raw[0] != 7:
            heap.free(raw)
            throw errors.failure("heap realloc did not preserve bytes")
        ..
    ..
    heap.free(raw)
    block := try heap.allocZero(32)
    # SAFETY: block names a live 32-byte allocation.
    unsafe:
        if block[0] != 0 || block[31] != 0:
            heap.free(block)
            throw errors.failure("heap allocZero did not clear bytes")
        ..
    ..
    block = try heap.reallocZero(block, 64, 32)
    # SAFETY: successful growth returned 64 bytes; indices 32 and 63 are valid.
    unsafe:
        if block[32] != 0 || block[63] != 0:
            heap.free(block)
            throw errors.failure("heap reallocZero did not clear growth")
        ..
    ..
    heap.free(block)
..
