mod main

use "std:allocator" as allocator
use "std:errors" as errors
use "std:executor" as executor
use "std:heap" as heap

increment(value u64*) u64:
    *value = *value + 1
    ret 0
..

pub main() !void:
    a allocator.Allocator = heap.allocator()
    scheduler := executor.singleThread()
    value u64 = 0

    pending := try scheduler.submit[u64](increment, addrof value)
    if value != 1:
        throw errors.failure("single-thread executor did not run work on submit")
    ..
    result u64 = try pending.await()
    if result != 0:
        throw errors.failure("single-thread executor returned the wrong task result")
    ..
    if value != 1:
        throw errors.failure("awaiting the completed task changed its result")
    ..
..
