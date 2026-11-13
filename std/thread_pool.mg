mod thread_pool
# Dynamically sized worker pools for asynchronous tasks.

use "std:allocator" as alc
use "std:cast" as cast
use "std:errors" as errors
use "std:executor" as executor
use "std:memory" as mem
use "std:mutex" as mutex
use "std:spinlock" as spinlock
use "std:thread" as thread
use "std:wake" as wake
use "std:cpu" as cpu
use "std:context" as context_module
use "std:checked" as checked
use "std:llvm" as ll

@platform("windows")
use "std:win/generation_wait" as generation_wait

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/generation_wait" as generation_wait

Task(
    entry fn(ptr) u64
    context ptr
    magmaContext context_module.Ctx
)

WorkerContext(
    state ptr
    index u64
)

State(
    allocator alc.Allocator
    workers thread.Thread*
    workerContexts WorkerContext**
    workerStates u8*
    workerCapacity u64
    maxWorkers u64
    minWorkers u64
    activeWorkers u64
    busyWorkers u64
    tasks Task*
    capacity u64
    head u64
    tail u64
    count u64
    pending u64
    idleWaiters u64
    sleepingWorkers u64
    wakeReservations u64
    workGeneration u32
    spinCount u64
    stopping bool
    fatalError error
    lock spinlock.SpinLock
    work generation_wait.Wait
    idle wake.Wake
)

cpuPause() void:
    ll.pause()
..

# Dynamically growing worker pool for independent pointer-context tasks.
# Submitted contexts remain caller-owned and must stay valid until their task ends.
pub ThreadPool impl executor.Executor(
    state State*
)

ThreadPool.submitRaw(entry ptr, context ptr) !void:
    try this.submit(entry, context)
..

ThreadPool.releaseRaw() void:
..

# Returns a borrowed, type-erased scheduling view of this pool.
# @ownership The pool must outlive the executor and all submitted tasks.
# @complexity O(1)
ThreadPool.executor() executor.Executor:
    ret this.protoBorrow()
..

releaseIdle(value $wake.Wake) void:
    value.free()
..

spawnWorkerInto(state State*, index u64) !bool:
    # SAFETY: index selects a reserved worker slot; its zero state means both
    # the handle and context slot are unoccupied before publication.
    unsafe:
        destination thread.Thread* = workerAt(state, index)
        context WorkerContext* = try state.allocator.allocT[WorkerContext](1)
        onerror state.allocator.free(context)
        context.state = state
        context.index = index
        worker thread.Thread = try thread.new[WorkerContext](workerMain, context)
        *destination = move worker
        *workerContextAt(state, index) = context
        state.workerStates[index] = 1
        state.activeWorkers = state.activeWorkers + 1
        ret true
    ..
..

taskAt(state State*, index u64) Task*:
    ret cast.reinterpret[Task](cast.utop(cast.ptou(state.tasks) + (index * sizeof Task)))
..

# Doubles and linearizes a full queue. The caller holds state.lock. Allocation
# happens before any state is changed, so a failure leaves the queue intact.
growQueue(state State*) !bool:
    # SAFETY: the caller holds the lock; count initialized ring entries are
    # moved into a newCapacity allocation before old storage is released.
    unsafe:
        maxU64 u64 = 0 - 1
        if state.capacity > maxU64 / 2:
            throw errors.wouldOverflow("thread pool queue capacity overflow")
        ..
        newCapacity := try checked.uMul(state.capacity, 2)
        newTasks Task* = try state.allocator.allocT[Task](newCapacity)
        for i u64 = 0 to state.count:
            source u64 = (state.head + i) % state.capacity
            destination Task* = cast.reinterpret[Task](cast.utop(cast.ptou(newTasks) + (i * sizeof Task)))
            *destination = *taskAt(state, source)
        ..
        state.allocator.free(state.tasks)
        state.tasks = newTasks
        state.capacity = newCapacity
        state.head = 0
        state.tail = state.count
        ret true
    ..
..

workerAt(state State*, index u64) thread.Thread*:
    ret cast.reinterpret[thread.Thread](cast.utop(cast.ptou(state.workers) + (index * sizeof thread.Thread)))
..

workerContextAt(state State*, index u64) WorkerContext**:
    ret cast.reinterpret[WorkerContext*](cast.utop(cast.ptou(state.workerContexts) + (index * sizeof WorkerContext*)))
..

# Expands worker bookkeeping geometrically. Worker contexts are individually
# allocated so moving these arrays cannot invalidate pointers held by workers.
growWorkerStorage(state State*) !bool:
    # SAFETY: workerCapacity bounds every old array; new arrays contain
    # newCapacity zeroed slots and uniquely receive each existing entry.
    unsafe:
    if state.workerCapacity >= state.maxWorkers:
        ret false
    ..
    maxU64 u64 = 0 - 1
    newCapacity u64 = state.workerCapacity
    if newCapacity > maxU64 / 2:
        newCapacity = state.maxWorkers
    else:
        newCapacity = newCapacity * 2
        if newCapacity > state.maxWorkers:
            newCapacity = state.maxWorkers
        ..
    ..

    newWorkers thread.Thread* = try state.allocator.allocT[thread.Thread](newCapacity)
    onerror state.allocator.free(newWorkers)

    newContexts WorkerContext** = try state.allocator.allocT[WorkerContext*](newCapacity)
    onerror state.allocator.free(newContexts)

    newStates u8* = try state.allocator.allocT[u8](newCapacity)
    onerror state.allocator.free(newStates)

    mem.zero(newWorkers, try checked.byteCount[thread.Thread](newCapacity))
    mem.zero(newContexts, try checked.byteCount[WorkerContext*](newCapacity))
    mem.zero(newStates, newCapacity)

    for i u64 = 0 to state.workerCapacity:
        newWorker thread.Thread* = cast.reinterpret[thread.Thread](cast.utop(cast.ptou(newWorkers) + (i * sizeof thread.Thread)))
        newContext WorkerContext** = cast.reinterpret[WorkerContext*](cast.utop(cast.ptou(newContexts) + (i * sizeof WorkerContext*)))
        *newWorker = *workerAt(state, i)
        *newContext = *workerContextAt(state, i)
        newStates[i] = state.workerStates[i]
    ..

    state.allocator.free(state.workers)
    state.allocator.free(state.workerContexts)
    state.allocator.free(state.workerStates)
    state.workers = newWorkers
    state.workerContexts = newContexts
    state.workerStates = newStates
    state.workerCapacity = newCapacity
      ret true
    ..
..

# Reaps an exited worker slot and starts a replacement. The caller holds the
# pool lock, so the new worker cannot inspect the queue until submission has
# finished publishing its task.
growWorkers(state State*) !bool:
    # SAFETY: the caller holds the pool lock; workerStates is the occupancy
    # metadata for worker handles and their separately allocated contexts.
    unsafe:
        oldCapacity := state.workerCapacity
        for index u64 = 0 to oldCapacity:
            status u8 = state.workerStates[index]
            if status != 1:
                if status == 2:
                    try workerAt(state, index).join()
                    state.allocator.free(*workerContextAt(state, index))
                    *workerContextAt(state, index) = none
                    state.workerStates[index] = 0
                ..
                ret try spawnWorkerInto(state, index)
            ..
        ..
        grown := try growWorkerStorage(state)
        if grown:
            ret try spawnWorkerInto(state, oldCapacity)
        ..
        ret false
    ..
..

lockResult(state State*) !bool:
    state.lock.lock()
    ret true
..

unlockResult(state State*) !bool:
    state.lock.unlock()
    ret true
..

waitIdleResult(state State*) !bool:
    try state.idle.wait()
    ret true
..

joinResult(state State*, index u64) !bool:
    try workerAt(state, index).join()
    ret true
..

recordFatal(state State*, failure error) void:
    locked bool, lockErr error = lockResult(state)
    if lockErr.ok():
        if state.fatalError.ok():
            state.fatalError = failure
        ..
        state.stopping = true
        sleepers u64 = state.sleepingWorkers
        state.sleepingWorkers = 0
        state.wakeReservations = 0
        state.lock.unlock()
        generation_wait.wakeAll(addrof state.work, addrof state.workGeneration, sleepers)
    else:
        state.fatalError = failure
        state.stopping = true
        generation_wait.wakeAll(addrof state.work, addrof state.workGeneration, state.activeWorkers)
    ..
    state.idle.notify()
..

workerMain(context WorkerContext*) u64:
    # SAFETY: spawnWorkerInto allocates context until this worker is joined;
    # queue and worker-state raw accesses are serialized by the pool lock.
    unsafe:
    state State* = context.state
    running bool = true
    loop running:
        locked bool, lockErr error = lockResult(state)
        if lockErr.nok():
            recordFatal(state, lockErr)
            ret 1
        ..

        if state.count != 0:
            task Task = *taskAt(state, state.head)
            state.head = (state.head + 1) % state.capacity
            state.count = state.count - 1
            state.busyWorkers = state.busyWorkers + 1
            unlocked bool, unlockErr error = unlockResult(state)
            if unlockErr.nok():
                recordFatal(state, unlockErr)
                ret 1
            ..

            ctx = task.magmaContext
            task.entry(task.context)
            completionLocked bool, completionLockErr error = lockResult(state)
            if completionLockErr.nok():
                recordFatal(state, completionLockErr)
                ret 1
            ..
            state.pending = state.pending - 1
            state.busyWorkers = state.busyWorkers - 1
            becameIdle bool = state.pending == 0
            idleWaiters u64 = state.idleWaiters
            completionUnlocked bool, completionUnlockErr error = unlockResult(state)
            if completionUnlockErr.nok():
                recordFatal(state, completionUnlockErr)
                ret 1
            ..
            if becameIdle:
                for i u64 = 0 to idleWaiters:
                    state.idle.notify()
                ..
            ..
        elif state.stopping:
            state.lock.unlock()
            running = false
        elif state.activeWorkers > state.minWorkers:
            # Keep the configured baseline and retire burst workers as soon as the
            # queue drains. Their joinable handles remain in their slots and
            # are reaped before reuse or during close.
            state.activeWorkers = state.activeWorkers - 1
            state.workerStates[context.index] = 2
            state.lock.unlock()
            running = false
        else:
            observed u32 = generation_wait.observe(addrof state.workGeneration)
            if state.spinCount != 0:
                unlocked bool, unlockErr error = unlockResult(state)
                if unlockErr.nok():
                    recordFatal(state, unlockErr)
                    ret 1
                ..
                spins u64 = 0
                loop spins < state.spinCount && generation_wait.observe(addrof state.workGeneration) == observed:
                    cpuPause()
                    spins = spins + 1
                ..
                if generation_wait.observe(addrof state.workGeneration) != observed:
                    continue
                ..
                spinLocked bool, spinLockErr error = lockResult(state)
                if spinLockErr.nok():
                    recordFatal(state, spinLockErr)
                    ret 1
                ..
                if state.count != 0 || state.stopping || generation_wait.observe(addrof state.workGeneration) != observed:
                    spinUnlocked bool, spinUnlockErr error = unlockResult(state)
                    if spinUnlockErr.nok():
                        recordFatal(state, spinUnlockErr)
                        ret 1
                    ..
                    continue
                ..
            ..
            state.sleepingWorkers = state.sleepingWorkers + 1
            unlocked bool, unlockErr error = unlockResult(state)
            if unlockErr.nok():
                recordFatal(state, unlockErr)
                ret 1
            ..
            waited bool, waitErr error = waitWorkResult(state, observed)
            if waitErr.nok():
                recordFatal(state, waitErr)
                ret 1
            ..
            wakeLocked bool, wakeLockErr error = lockResult(state)
            if wakeLockErr.nok():
                recordFatal(state, wakeLockErr)
                ret 1
            ..
            if state.sleepingWorkers != 0:
                state.sleepingWorkers = state.sleepingWorkers - 1
            ..
            if state.wakeReservations != 0:
                state.wakeReservations = state.wakeReservations - 1
            ..
            wakeUnlocked bool, wakeUnlockErr error = unlockResult(state)
            if wakeUnlockErr.nok():
                recordFatal(state, wakeUnlockErr)
                ret 1
            ..
        ..
    ..
      ret 0
    ..
..

waitWorkResult(state State*, observed u32) !bool:
    try generation_wait.wait(addrof state.work, addrof state.workGeneration, observed)
    ret true
..

newConfigured(a alc.Allocator, minWorkers u64, maxWorkers u64, queueCapacity u64, spinCount u64) !$ThreadPool:
    # SAFETY: all raw arrays are allocated to their recorded capacities and
    # zeroed before publication; cleanup counters cover only spawned workers.
    unsafe:
    if minWorkers == 0 || maxWorkers < minWorkers || queueCapacity == 0:
        throw errors.invalidArgument("thread pool sizes or limits are invalid")
    ..
    state State* = try a.allocT[State](1)
    onerror a.free(state)

    mem.zero(state, sizeof State)
    tasks Task* = try a.allocT[Task](queueCapacity)
    onerror a.free(tasks)

    workers thread.Thread* = try a.allocT[thread.Thread](minWorkers)
    onerror a.free(workers)

    workerContexts WorkerContext** = try a.allocT[WorkerContext*](minWorkers)
    onerror a.free(workerContexts)

    workerStates u8* = try a.allocT[u8](minWorkers)
    onerror a.free(workerStates)

    mem.zero(workers, try checked.byteCount[thread.Thread](minWorkers))
    mem.zero(workerContexts, try checked.byteCount[WorkerContext*](minWorkers))
    mem.zero(workerStates, minWorkers)

    lock := spinlock.new()
    work generation_wait.Wait = try generation_wait.new()
    onerror generation_wait.free(addrof work)
    
    idle wake.Wake = try wake.new(wake.condition())
    state.allocator = a
    state.workers = workers
    state.workerContexts = workerContexts
    state.workerStates = workerStates
    state.workerCapacity = minWorkers
    state.maxWorkers = maxWorkers
    state.minWorkers = minWorkers
    state.tasks = tasks
    state.capacity = queueCapacity
    state.spinCount = spinCount
    state.lock = lock
    state.work = work
    state.idle = move idle
    onerror state.idle.free()

    i u64 = 0
    onerror:
        state.stopping = true
        generation_wait.wakeAll(addrof state.work, addrof state.workGeneration, i)
        for j u64 = 0 to i:
            workerAt(state, j).join()
            a.free(*workerContextAt(state, j))
        ..
    ..

    loop i < minWorkers:
        try spawnWorkerInto(state, i)
        i = i + 1
    ..
      ret ThreadPool(state=state)
    ..
..

# Creates a pool with explicit worker, queue, and idle-spinning limits.
# @param spinCount idle polling iterations before a worker sleeps
# @warning maxWorkers must be at least minWorkers and all size arguments must be nonzero where required.
# @complexity O(minWorkers + queueCapacity)
# @ownership The returned pool must be closed.
# @example
#   pool := try thread_pool.new(a, 2, 8, 256, 1)
pub new(a alc.Allocator, minWorkers u64, maxWorkers u64, queueCapacity u64, spinCount u64) !$ThreadPool:
    ret try newConfigured(a, minWorkers, maxWorkers, queueCapacity, spinCount)
..

# Creates a pool sized from the machine's logical core count, with an initial
# 256-task queue and permission to grow workers as demand increases.
# @complexity O(C), where C is the detected core count
# @ownership The returned pool must be closed.
# @example
#   pool := try thread_pool.newDefault(a)
pub newDefault(a alc.Allocator) !$ThreadPool:
    threadCount := cpu.coreCount()
    maxThreads u64 = 0 - 1
    spinCount := threadCount / 3

    if spinCount < 1:
        spinCount = 1
    ..
    ret try newConfigured(a, threadCount, maxThreads, 256, spinCount)
..

# Queues entry(context) for execution and grows the worker set when useful.
# @ownership context remains caller-owned and must remain valid until wait() succeeds.
# @throws failure if the pool is stopping or a worker previously failed
# @complexity O(1) amortized; allocation or worker creation can occur
# @example
#   try pool.submit(runTask, context)
ThreadPool.submit(entry fn(ptr) u64, context ptr) !void:
    # SAFETY: the pool lock protects queue occupancy; growQueue guarantees a
    # free task slot and tail is always reduced modulo capacity.
    unsafe:
    if this.state == none:
        throw errors.invalidArgument("failed to submit to pool, invalid state")
    ..
    if entry == none:
        throw errors.invalidArgument("invalid thread pool submission")
    ..
    state State* = this.state
    state.lock.lock()
    onerror state.lock.unlock()
    throw state.fatalError
    if state.stopping:
        throw errors.failure("thread pool is stopping")
    ..
    if state.count == state.capacity:
        grown bool, growErr error = growQueue(state)
        throw growErr
    ..
    nextPending := try checked.uAdd(state.pending, 1)
    # Queueing this task would consume more workers than are currently idle.
    # Grow by one, up to the configured maximum. Repeated submissions during a
    # burst therefore ramp the pool up without creating surplus threads.
    idleWorkers u64 = state.activeWorkers - state.busyWorkers
    if state.count + 1 > idleWorkers && state.activeWorkers < state.maxWorkers:
        try growWorkers(state)
    ..
    destination Task* = taskAt(state, state.tail)
    *destination = Task(entry=entry, context=context, magmaContext=ctx)
    state.tail = (state.tail + 1) % state.capacity
    state.count = state.count + 1
    state.pending = nextPending
    shouldWake bool = state.sleepingWorkers > state.wakeReservations
    if shouldWake:
        state.wakeReservations = state.wakeReservations + 1
    ..
    state.lock.unlock()
    if shouldWake:
        generation_wait.wakeOne(addrof state.work, addrof state.workGeneration)
    elif state.spinCount != 0:
        generation_wait.signal(addrof state.workGeneration)
      ..
    ..
..

# Blocks until every task submitted before or during the wait has completed.
# @throws the first fatal worker or synchronization error
# @complexity O(1) setup plus blocking time for pending work
# @example
#   try pool.wait()
ThreadPool.wait() !void:
    state State* = this.state
    waiting bool = true
    loop waiting:
        state.lock.lock()
        onerror state.lock.unlock()
        throw state.fatalError
        waiting = state.pending != 0
        if waiting:
            state.idleWaiters = state.idleWaiters + 1
        ..
        state.lock.unlock()
        if waiting:
            waited bool, waitErr error = waitIdleResult(state)
            state.lock.lock()
            state.idleWaiters = state.idleWaiters - 1
            state.lock.unlock()
            throw waitErr
        ..
    ..
..

# Waits for pending work, stops and joins all workers, then releases pool storage.
# @warning Do not submit concurrently once close begins.
# @complexity O(W + Q) plus time required for pending tasks, where W is workers
# @example
#   try pool.close()
destr ThreadPool.close() !void:
    # SAFETY: stopping prevents new work; each occupied worker/context slot is
    # joined/freed once before all capacity-sized arrays and State are released.
    unsafe:
    if this.state == none:
        throw errors.invalidArgument("thread pool is not active")
    ..
    state State* = this.state
    try this.wait()
    state.lock.lock()
    state.stopping = true
    sleepers u64 = state.sleepingWorkers
    state.sleepingWorkers = 0
    state.wakeReservations = 0
    state.lock.unlock()
    generation_wait.wakeAll(addrof state.work, addrof state.workGeneration, sleepers)
    for i u64 = 0 to state.workerCapacity:
        if state.workerStates[i] != 0:
            try workerAt(state, i).join()
            state.allocator.free(*workerContextAt(state, i))
        ..
    ..
    try state.idle.free()
    generation_wait.free(addrof state.work)
    state.allocator.free(state.workers)
    state.allocator.free(state.workerContexts)
    state.allocator.free(state.workerStates)
    state.allocator.free(state.tasks)
    state.allocator.free(state)
      this.state = none
    ..
..
