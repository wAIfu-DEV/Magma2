mod main

use "std:errors" as errors
use "std:thread" as thread

worker(value u64*) u64:
    # SAFETY: every thread is started with addrof a u64 that remains live until
    # the corresponding join completes.
    *value = 42
    ret 0
..

pub main() !void:
    value u64 = 0
    t := try thread.new[u64](worker, addrof value)
    try t.join()

    if value != 42:
        throw errors.failure("thread did not publish its result before join")
    ..

    thread.yield()

    valueA u64 = 0
    valueB u64 = 0
    threads := [2]thread.Thread
    threads[0] = try thread.new[u64](worker, addrof valueA)
    threads[1] = try thread.new[u64](worker, addrof valueB)
    try thread.joinAll(threads)
    if valueA != 42 || valueB != 42:
        throw errors.failure("joinAll returned before every thread finished")
    ..
..
