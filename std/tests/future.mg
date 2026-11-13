mod main

use "std:allocator" as allocator
use "std:errors" as errors
use "std:future" as future
use "std:heap" as heap
use "std:thread_pool" as thread_pool
use "std:abort" as abort
use "std:time" as time

doubleValue(context u64*) !u64:
    ret *context * 2
..

waitForAbort(context u64*, signal abort.Signal) !u64:
    loop signal.isAborted() == false:
        time.sleep(1)
    ..
    try signal.check()
    ret *context
..

pub main() !void:
    a allocator.Allocator = heap.allocator()
    pool := try thread_pool.new(a, 1, 1, 8, 1)

    scheduler := pool.executor()
    direct := try future.new[u64, u64](scheduler, doubleValue, 21)
    if try direct.await() != 42:
        try pool.close()
        throw errors.failure("direct Future returned the wrong value")
    ..

    aborted := try future.newAbort[u64, u64](scheduler, waitForAbort, 1)
    aborted.abort()
    ignored u64, abortError error = aborted.await()
    if errors.hasCode(abortError, errors.ERR_CANCELLED) == false:
        try pool.close()
        throw errors.failure("aborted Future returned the wrong error")
    ..

    try pool.close()
..
