mod main

use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:heap" as heap
use "std:thread_pool" as thread_pool
use "std:thread" as thread
use "std:time" as time
use "std:footgun" as footgun
use "std:llvm" as ll

ScaleContext(
    ready u64*
    release u64*
)

atomicAdd(target u64*, value u64) void:
    ll.atomicFetchAddAcqRelU64(target, value)
..

atomicLoad(target u64*) u64:
    ret ll.atomicLoadAcquireU64(target)
..

atomicStore(target u64*, value u64) void:
    ll.atomicStoreReleaseU64(target, value)
..

occupy(raw ptr) u64:
    # SAFETY: submissions pass addrof a live ScaleContext and wait before its
    # scope exits.
    unsafe:
        context ScaleContext* = raw
        atomicAdd(context.ready, 1)
        loop atomicLoad(context.release) == 0:
            thread.yield()
        ..
    ..
    ret 0
..

increment(raw ptr) u64:
    # SAFETY: each submission passes addrof a live u64 and waits before scope
    # exit; these test pools serialize increment tasks.
    unsafe:
        value u64* = raw
        *value = *value + 1
    ..
    ret 0
..

shutdownResult(pool thread_pool.ThreadPool*) !bool:
    try pool.close()
    ret true
..

expectInvalidSizes() !void:
    a := ctx.alloc
    zeroWorkers thread_pool.ThreadPool, workerErr error = thread_pool.new(a, 0, 1, 1, 1)
    if workerErr.ok():
        footgun.drop[thread_pool.ThreadPool](move zeroWorkers)
        throw errors.failure("thread pool accepted zero workers")
    ..
    if workerErr.code() != 2:
        throw errors.failure("thread pool returned the wrong zero-worker error")
    ..

    invertedWorkers thread_pool.ThreadPool, limitErr error = thread_pool.new(a, 2, 1, 1, 1)
    if limitErr.ok():
        footgun.drop[thread_pool.ThreadPool](move invertedWorkers)
        throw errors.failure("thread pool accepted a maximum below its minimum")
    ..
    if limitErr.code() != 2:
        throw errors.failure("thread pool returned the wrong limit error")
    ..

    zeroCapacity thread_pool.ThreadPool, capacityErr error = thread_pool.new(a, 1, 1, 0, 1)
    if capacityErr.ok():
        footgun.drop[thread_pool.ThreadPool](move zeroCapacity)
        throw errors.failure("thread pool accepted zero queue capacity")
    ..
    if capacityErr.code() != 2:
        throw errors.failure("thread pool returned the wrong capacity error")
    ..

..

pub main() !void:
    a allocator.Allocator = heap.allocator()
    try expectInvalidSizes()

    defaultPool := try thread_pool.newDefault(a)
    try defaultPool.close()

    value u64 = 0
    pool := try thread_pool.new(a, 1, 1, 8, 1)

    # Exercise more tasks than the ring capacity across several idle cycles.
    round u64 = 0
    loop round < 4:
        i u64 = 0
        loop i < 8:
            try pool.submit(increment, addrof value)
            i = i + 1
        ..
        try pool.wait()
        round = round + 1
    ..
    if value != 32:
        try pool.close()
        throw errors.failure("thread pool did not execute every task")
    ..

    # Waiting at an already-idle point must return immediately.
    try pool.wait()
    try pool.submit(increment, addrof value)
    try pool.close()
    if value != 33:
        throw errors.failure("thread pool shutdown did not drain queued work")
    ..

    # A separately constructed inactive handle exercises defensive rejection
    # without using the already consumed pool value.
    inactive := thread_pool.ThreadPool(state=none)
    stopped bool, shutdownErr error = shutdownResult(addrof inactive)
    if shutdownErr.code() != 2:
        throw errors.failure("thread pool accepted an inactive handle")
    ..

    spinningValue u64 = 0
    spinning := try thread_pool.new(a, 1, 1, 8, 4096)
    spinRound u64 = 0
    loop spinRound < 100:
        spinIndex u64 = 0
        loop spinIndex < 8:
            try spinning.submit(increment, addrof spinningValue)
            spinIndex = spinIndex + 1
        ..
        try spinning.wait()
        spinRound = spinRound + 1
    ..
    try spinning.close()
    if spinningValue != 800:
        throw errors.failure("spinning thread pool did not execute every task")
    ..

    # A tiny initial ring must grow enough to accept a large submission burst.
    growingValue u64 = 0
    growing := try thread_pool.new(a, 1, 1, 1, 1)
    growingIndex u64 = 0
    loop growingIndex < 10000:
        try growing.submit(increment, addrof growingValue)
        growingIndex = growingIndex + 1
    ..
    try growing.close()
    if growingValue != 10000:
        throw errors.failure("thread pool queue did not grow correctly")
    ..

    # The configured maximum is a ceiling. A pool starts at its minimum,
    # grows while queued work has consumed every available worker, then returns
    # then returns to that minimum after the burst drains.
    ready u64 = 0
    release u64 = 0
    scaleContext := ScaleContext(ready=addrof ready, release=addrof release)
    scaling := try thread_pool.new(a, 2, 4, 4, 1)
    if scaling.state.workerCapacity != 2:
        try scaling.close()
        throw errors.failure("thread pool allocated its maximum worker storage eagerly")
    ..
    scaleIndex u64 = 0
    loop scaleIndex < 4:
        try scaling.submit(occupy, addrof scaleContext)
        scaleIndex = scaleIndex + 1
    ..
    deadline u64 = time.ticks() + time.msToTicks(2000)
    loop atomicLoad(addrof ready) != 4 && time.ticks() < deadline:
        thread.yield()
    ..
    if atomicLoad(addrof ready) != 4:
        atomicStore(addrof release, 1)
        try scaling.close()
        throw errors.failure("thread pool did not grow when all workers were busy")
    ..
    if scaling.state.workerCapacity != 4 || scaling.state.workerCapacity > scaling.state.activeWorkers * 2:
        atomicStore(addrof release, 1)
        try scaling.close()
        throw errors.failure("thread pool worker storage did not grow geometrically")
    ..
    atomicStore(addrof release, 1)
    try scaling.wait()
    shrinkDeadline u64 = time.ticks() + time.msToTicks(2000)
    active u64 = 4
    loop active != 2 && time.ticks() < shrinkDeadline:
        scaling.state.lock.lock()
        active = scaling.state.activeWorkers
        scaling.state.lock.unlock()
        thread.yield()
    ..
    if active != 2:
        try scaling.close()
        throw errors.failure("thread pool did not shrink after its burst drained")
    ..
    try scaling.close()

..
