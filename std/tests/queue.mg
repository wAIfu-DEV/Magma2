mod main

use "std:allocator" as allocator
use "std:errors" as errors
use "std:heap" as heap
use "std:queue" as queue
use "std:cast" as cast

pub main() !void:
    a allocator.Allocator = heap.allocator()
    values := try queue.new[u64](none)
    defer values.free()
    try values.enqueue(3)
    try values.enqueue(7)
    first := try values.dequeue()
    if first != 3 || values.count() != 1:
        throw errors.failure("queue behavior changed")
    ..
    if values.view()[0] != 7:
        throw errors.failure("queue view changed")
    ..
    try values.clear()
    if values.count() != 0:
        throw errors.failure("queue clear changed")
    ..
..
