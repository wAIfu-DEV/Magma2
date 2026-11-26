mod main

use "std:errors" as errors

increment(value u64*) u64:
    *value = *value + 1
    ret 0
..

pub main() !void:
    allocation u8*, allocationError error = ctx.alloc.alloc(1)
    if allocationError.ok():
        ctx.alloc.free(allocation)
        throw errors.failure("naked default context unexpectedly allocated memory")
    ..

    value u64 = 0
    pending := try ctx.exec.submit[u64](increment, addrof value)
    if value != 1:
        throw errors.failure("naked default executor did not run work on submit")
    ..
    result u64 = try pending.await()
    if result != 0:
        throw errors.failure("naked default executor returned the wrong result")
    ..
..
