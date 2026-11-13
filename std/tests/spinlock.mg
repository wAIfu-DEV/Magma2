mod main

use "std:atomic" as atomic
use "std:errors" as errors
use "std:spinlock" as spinlock
use "std:thread" as thread

const workerCount u64 = 4
const incrementsPerWorker u64 = 10000

Context(
    lock spinlock.SpinLock*
    value u64*
    ready atomic.U64*
    start atomic.U64*
)

worker(context Context*) u64:
    context.ready.fetchAdd(1)
    loop context.start.load() == 0:
        thread.yield()
    ..

    i u64 = 0
    loop i < incrementsPerWorker:
        context.lock.lock()
        *context.value = *context.value + 1
        context.lock.unlock()
        i = i + 1
    ..
    ret 0
..

pub main() !void:
    lock := spinlock.new()
    value u64 = 0
    ready := atomic.newU64(0)
    start := atomic.newU64(0)
    contexts := [4]Context
    threads := [4]thread.Thread

    i u64 = 0
    loop i < workerCount:
        contexts[i] = Context(lock=addrof lock, value=addrof value, ready=addrof ready, start=addrof start)
        threads[i] = try thread.new[Context](worker, addrof contexts[i])
        i = i + 1
    ..
    loop ready.load() != workerCount:
        thread.yield()
    ..
    start.store(1)
    try thread.joinAll(threads)

    if value != workerCount * incrementsPerWorker:
        throw errors.failure("spinlock did not provide mutual exclusion")
    ..
..
