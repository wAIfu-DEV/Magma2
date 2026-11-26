mod main

use "std:allocator" as allocator
use "std:errors" as errors
use "std:executor" as executor
use "std:future" as future
use "std:heap" as heap
use "std:thread_pool" as thread_pool
use "std:abort" as abort
use "std:time" as time

doubleValue(context u64*) !u64:
    ret *context * 2
..

readAwaitable(context u64*) !u64:
    ret *context
..

waitForAbort(context u64*, signal abort.Signal) !u64:
    loop signal.isAborted() == false:
        time.sleep(1)
    ..
    try signal.check()
    ret *context
..

pub main() !void:
    immediate u64 = 42
    ready executor.Awaitable[u64, u64] = executor.Awaitable[u64, u64](
        value=0,
        context=addrof immediate,
        awaitRaw=readAwaitable,
    )
    if try ready.await() != 42:
        throw errors.failure("Awaitable returned the wrong value")
    ..

    a allocator.Allocator = heap.allocator()

    singleScheduler := executor.singleThread()
    serialFuture := try future.new[u64, u64](singleScheduler, doubleValue, 21)
    if try serialFuture.await() != 42:
        throw errors.failure("single-thread executor Future returned the wrong value")
    ..

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
