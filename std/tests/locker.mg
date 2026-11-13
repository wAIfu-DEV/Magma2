mod main

use "std:atomic" as atomic
use "std:errors" as errors
use "std:locker" as locker
use "std:mutex" as mutex
use "std:spinlock" as spinlock
use "std:thread" as thread

const workerCount u64 = 4
const incrementsPerWorker u64 = 10000

Context(
    lock locker.Locker*
    value u64*
    ready atomic.U64*
    start atomic.U64*
    failed atomic.U64*
)

lockResult(lock locker.Locker*) !bool:
    try lock.lock()
    ret true
..

unlockResult(lock locker.Locker*) !bool:
    try lock.unlock()
    ret true
..

worker(context Context*) u64:
    context.ready.fetchAdd(1)
    loop context.start.load() == 0:
        thread.yield()
    ..

    i u64 = 0
    loop i < incrementsPerWorker:
        locked bool, lockErr error = lockResult(context.lock)
        if lockErr.nok():
            context.failed.store(1)
            ret 1
        ..
        *context.value = *context.value + 1
        unlocked bool, unlockErr error = unlockResult(context.lock)
        if unlockErr.nok():
            context.failed.store(1)
            ret 1
        ..
        i = i + 1
    ..
    ret 0
..

testLocker(lock locker.Locker*, failureMessage str) !void:
    value u64 = 0
    ready := atomic.newU64(0)
    start := atomic.newU64(0)
    failed := atomic.newU64(0)
    contexts := [4]Context
    threads := [4]thread.Thread

    i u64 = 0
    loop i < workerCount:
        contexts[i] = Context(lock=lock, value=addrof value, ready=addrof ready, start=addrof start, failed=addrof failed)
        threads[i] = try thread.new[Context](worker, addrof contexts[i])
        i = i + 1
    ..
    loop ready.load() != workerCount:
        thread.yield()
    ..
    start.store(1)
    try thread.joinAll(threads)

    if failed.load() != 0 || value != workerCount * incrementsPerWorker:
        throw errors.failure(failureMessage)
    ..
..

pub main() !void:
    mutexBackend := try mutex.new()
    mutexLocker := mutexBackend.locker()
    try testLocker(addrof mutexLocker, "mutex-backed locker did not provide mutual exclusion")
    try mutexBackend.free()

    spinlockBackend := spinlock.new()
    spinlockLocker := spinlockBackend.locker()
    try testLocker(addrof spinlockLocker, "spinlock-backed locker did not provide mutual exclusion")
..
