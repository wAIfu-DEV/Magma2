mod future
use "std:llvm" as ll
# Owned asynchronous results that can be awaited and released safely.

use "std:allocator" as alc
use "std:cast" as cast
use "std:errors" as errors
use "std:executor" as executor
use "std:time" as time
use "std:abort" as abort

State[T](
    allocator alc.Allocator
    value T
    failure error
    status u32
    references u32
    controller abort.Controller
)

Work[T, Context](
    state State[T]
    entry fn(Context*) !T
    abortEntry fn(Context*, abort.Signal) !T
    context Context
    abortable bool
)

# Single-consumer asynchronous result backed by worker-pool state.
# @mustcall await
pub Future[T](
    state State[T]*
    task executor.Awaitable[u64, executor.RawTask]
)

atomicAdd(target u64*, value u64) void:
    ll.atomicFetchAddRelaxedU64(target, value)
..

atomicLoad(target u64*) u64:
    ret ll.atomicLoadRelaxedU64(target)
..

atomicStore(target u64*, value u64) void:
    ll.atomicStoreRelaxedU64(target, value)
..

publishDone(status u32*) void:
    ll.atomicStoreReleaseU32(status, 1)
..

loadStatus(status u32*) u32:
    ret ll.atomicLoadAcquireU32(status)
..

releaseReference(references u32*) u32:
    ret ll.atomicFetchSubAcqRelU32(references, 1)
..

releaseState[T](state State[T]*) void:
    if releaseReference(addrof state.references) == 1:
        # SAFETY: the last reference uniquely owns the embedded controller.
        unsafe:
            state.controller.close()
        ..
        state.allocator.free(state)
    ..
..

taskMain[T, Context](work Work[T, Context]*) u64:
    state State[T]* = addrof work.state
    allowed bool, abortFailure error = checkBeforeStart(state.controller.signal())
    if abortFailure.nok():
        state.failure = abortFailure
    elif work.abortable:
        abortValue T, workAbortFailure error = work.abortEntry(addrof work.context, state.controller.signal())
        if workAbortFailure.ok():
            unsafe: state.value = abortValue ..
        else:
            state.failure = workAbortFailure
        ..
    else:
        plainValue T, plainFailure error = work.entry(addrof work.context)
        if plainFailure.ok():
            unsafe: state.value = plainValue ..
        else:
            state.failure = plainFailure
        ..
    ..
    publishDone(addrof state.status)
    releaseState[T](state)
    ret 0
..

checkBeforeStart(signal abort.Signal) !bool:
    try signal.check()
    ret true
..

submitWork[T, Context](scheduler executor.Executor, work Work[T, Context]*) !executor.Awaitable[u64, executor.RawTask]:
    ret try scheduler.submit[Work[T, Context]](taskMain[T, Context], work)
..

# Future backend using atomic publication and a platform completion wait.
# @complexity O(1) to allocate and submit
# @param a allocator for task and result state
# @param scheduler executor that runs entry
# @param entry function producing the result
# @param context context copied into task storage
# @returns owned active future
# @ownership scheduler is borrowed for submission; its implementation and a
# must remain valid until await completes.
# @example
#   scheduler := pool.executor()
#   pending := try future.new[u64, Work](scheduler, run, work)
pub new[T, Context](scheduler executor.Executor, entry fn(Context*) !T, context Context) !$Future[T]:
    a := ctx.alloc
    work Work[T, Context]* = try a.allocT[Work[T, Context]](1)
    onerror a.free(work)
    state State[T]* = addrof work.state
    state.allocator = a
    state.failure = errors.ok()
    state.status = 0
    state.references = 2
    state.controller = try abort.new()
    onerror closeController[T](state)
    work.entry = entry
    work.abortEntry = none
    work.context = context
    work.abortable = false

    task := try submitWork[T, Context](scheduler, work)
    ret Future[T](state=state, task=task)
..

# Creates a future whose work receives the future's abort signal.
pub newAbort[T, Context](scheduler executor.Executor, entry fn(Context*, abort.Signal) !T, context Context) !$Future[T]:
    a := ctx.alloc
    work Work[T, Context]* = try a.allocT[Work[T, Context]](1)
    onerror a.free(work)
    state State[T]* = addrof work.state
    state.allocator = a
    state.failure = errors.ok()
    state.status = 0
    state.references = 2
    state.controller = try abort.new()
    onerror closeController[T](state)
    work.entry = none
    work.abortEntry = entry
    work.context = context
    work.abortable = true
    task := try submitWork[T, Context](scheduler, work)
    ret Future[T](state=state, task=task)
..

closeController[T](state State[T]*) void:
    # SAFETY: used only during construction before state is published.
    unsafe:
        state.controller.close()
    ..
..

# Requests cooperative cancellation. The future must still be awaited.
Future[T].abort() void:
    if this.state != none:
        this.state.controller.abort()
    ..
..

Future[T].abortAfter(relativeMs u64) !void:
    if this.state == none:
        throw errors.invalidArgument("future is not active")
    ..
    try this.state.controller.abortAfter(relativeMs)
..

Future[T].isAbortRequested() !bool:
    if this.state == none:
        throw errors.invalidArgument("future is not active")
    ..
    ret this.state.controller.isAborted()
..

# Reports whether the worker has published a result without consuming it.
# @complexity O(1)
# @throws invalidArgument after the future has been consumed
# @example
#   complete := try pending.isDone()
Future[T].isDone() !bool:
    if this.state == none:
        throw errors.invalidArgument("future is not active")
    ..
    state State[T]* = this.state
    ret loadStatus(addrof state.status) != 0
..

# Blocks until completion, consumes the future, and returns ownership of its result.
# @complexity O(1) when complete; otherwise blocks without busy-waiting
# @throws the error returned by the worker entry function
# @throws invalidArgument when the future was already consumed
# @example
#   value := try pending.await()
destr Future[T].await() !$T:
    if this.state == none:
        throw errors.invalidArgument("future is not active")
    ..
    state State[T]* = this.state
    this.state = none
    task executor.Awaitable[u64, executor.RawTask] = move this.task
    ignored u64 = try task.await()
    if state.failure.nok():
        failure error = state.failure
        releaseState[T](state)
        throw failure
    ..
    value $T = state.value
    releaseState[T](state)
    ret move value
..
