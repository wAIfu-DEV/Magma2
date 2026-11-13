mod main
use "std:allocator" as allocator
use "std:errors" as errors
use "std:heap" as heap
use "std:slices" as slices
pub main() !void:
    a allocator.Allocator = heap.allocator()
    empty := slices.fromPtr(none, 0)
    if slices.count(empty) != 0:
        throw errors.failure("empty slice construction changed")
    ..
    view := try slices.alloc[u8](4)
    block := slices.toPtr(view)
    if slices.count(view) != 4 || slices.toPtr(view) != block:
        throw errors.failure("slice behavior changed")
    ..
    words := try slices.reinterpret[u8, u16](view)
    if slices.count(words) != 2:
        slices.free(view)
        throw errors.failure("slice reinterpret changed")
    ..
    slices.free(view)
..
