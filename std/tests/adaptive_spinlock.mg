mod main

use "std:adaptive_spinlock" as adaptive_spinlock
use "std:atomic" as atomic
use "std:errors" as errors
use "std:thread" as thread

const WORKERS u64 = 4
const ITERATIONS u64 = 10000

Context(
    lock adaptive_spinlock.AdaptiveSpinLock*
    counter u64*
    ready atomic.U64*
    start atomic.U64*
)

worker(context Context*) u64:
    context.ready.fetchAdd(1)
    loop context.start.loadAcquire() == 0:
        thread.yield()
    ..
    for i u64 = 0 to ITERATIONS:
        context.lock.lock()
        *context.counter = *context.counter + 1
        context.lock.unlock()
    ..
    ret 0
..

pub main() !void:
    lock := adaptive_spinlock.new()
    counter u64 = 0
    ready := atomic.newU64(0)
    start := atomic.newU64(0)
    contexts := [4]Context
    workers := [4]thread.Thread
    for i u64 = 0 to WORKERS:
        contexts[i] = Context(lock=addrof lock, counter=addrof counter, ready=addrof ready, start=addrof start)
        workers[i] = try thread.new[Context](worker, addrof contexts[i])
    ..
    loop ready.loadAcquire() != WORKERS:
        thread.yield()
    ..
    start.storeRelease(1)
    try thread.joinAll(workers)
    if counter != WORKERS * ITERATIONS:
        throw errors.failure("adaptive spin lock did not provide mutual exclusion")
    ..

    view := lock.locker()
    try view.lock()
    try view.unlock()
..
