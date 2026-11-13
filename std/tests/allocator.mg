mod main
use "std:allocator" as allocator
use "std:heap" as heap
pub main() !void:
    a allocator.Allocator = heap.allocator()
    block := try a.alloc(16)
    block = try a.realloc(block, 32)
    a.free(block)
..
