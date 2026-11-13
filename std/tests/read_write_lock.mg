mod main

use "std:atomic" as atomic
use "std:errors" as errors
use "std:read_write_lock" as read_write_lock
use "std:thread" as thread

Context(
    lock read_write_lock.ReadWriteLock*
    ready atomic.U64*
    writerReady atomic.U64*
    start atomic.U64*
    activeReaders atomic.U64*
    writerActive atomic.U64*
    value u64*
    failed atomic.U64*
)

reader(context Context*) u64:
    context.lock.readLock()
    context.activeReaders.fetchAdd(1)
    if context.writerActive.load() != 0:
        context.failed.store(1)
    ..
    context.ready.fetchAdd(1)
    loop context.start.loadAcquire() == 0:
        thread.yield()
    ..
    if context.writerActive.load() != 0:
        context.failed.store(1)
    ..
    context.activeReaders.fetchSub(1)
    context.lock.readUnlock()
    ret 0
..

writer(context Context*) u64:
    context.writerReady.fetchAdd(1)
    context.lock.writeLock()
    if context.activeReaders.load() != 0 || context.writerActive.exchange(1) != 0:
        context.failed.store(1)
    ..
    *context.value = *context.value + 1
    context.writerActive.store(0)
    context.lock.writeUnlock()
    ret 0
..

pub main() !void:
    lock := read_write_lock.new()
    ready := atomic.newU64(0)
    writerReady := atomic.newU64(0)
    start := atomic.newU64(0)
    activeReaders := atomic.newU64(0)
    writerActive := atomic.newU64(0)
    value u64 = 0
    failed := atomic.newU64(0)

    first := Context(lock=addrof lock, ready=addrof ready, writerReady=addrof writerReady, start=addrof start, activeReaders=addrof activeReaders, writerActive=addrof writerActive, value=addrof value, failed=addrof failed)
    second := Context(lock=addrof lock, ready=addrof ready, writerReady=addrof writerReady, start=addrof start, activeReaders=addrof activeReaders, writerActive=addrof writerActive, value=addrof value, failed=addrof failed)
    writerContext := Context(lock=addrof lock, ready=addrof ready, writerReady=addrof writerReady, start=addrof start, activeReaders=addrof activeReaders, writerActive=addrof writerActive, value=addrof value, failed=addrof failed)

    firstThread := try thread.new[Context](reader, addrof first)
    secondThread := try thread.new[Context](reader, addrof second)
    loop ready.loadAcquire() != 2:
        thread.yield()
    ..

    writerThread := try thread.new[Context](writer, addrof writerContext)
    loop writerReady.loadAcquire() != 1:
        thread.yield()
    ..
    start.storeRelease(1)

    try firstThread.join()
    try secondThread.join()
    try writerThread.join()
    if failed.load() != 0 || value != 1 || activeReaders.load() != 0 || writerActive.load() != 0:
        throw errors.failure("read/write lock did not provide shared and exclusive access")
    ..
..
