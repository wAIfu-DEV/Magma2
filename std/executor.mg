mod executor

# Type-erased task scheduler. Executor is a borrowed view: its implementation
# must remain valid until every submitted task has completed.

pub proto Executor(
    submitRaw(entry ptr, context ptr) !Awaitable[u64, RawTask]
    releaseRaw() void
)

use "std:errors" as errors

pub RawTask(handle ptr)

# A single-consumption operation whose result becomes available when awaited.
# The context must remain valid until await() completes.
pub Awaitable[T, Context](
    value T
    context Context*
    awaitRaw fn(Context*) !T
)

destr Awaitable[T, Context].await() !$T:
    if this.awaitRaw == none:
        ret this.value
    ..
    ret try this.awaitRaw(this.context)
..

InlineTask(
    entry fn(ptr) u64
    context ptr
)

pub SingleThreadExecutor impl Executor(value u8)

# Runs work immediately on the calling thread and returns a completed awaitable.
SingleThreadExecutor.submitRaw(entry ptr, context ptr) !Awaitable[u64, RawTask]:
    task := InlineTask(entry=entry, context=context)
    ret Awaitable[u64, RawTask](value=task.entry(task.context), context=none, awaitRaw=none)
..

SingleThreadExecutor.releaseRaw() void:
..

gl_singleThreadExecutor := SingleThreadExecutor(value=0)

pub noctx singleThread() Executor:
    ret gl_singleThreadExecutor.protoBorrow()
..

NullExecutor impl Executor(value u8)

NullExecutor.submitRaw(entry ptr, context ptr) !Awaitable[u64, RawTask]:
    throw errors.invalidArgument("executor is unavailable in the null context")
..

NullExecutor.releaseRaw() void:
..

gl_nullExecutor := NullExecutor(value=0)

pub noctx null() Executor:
    ret gl_nullExecutor.protoBorrow()
..

# Schedules entry(context) for execution.
# @ownership context remains caller-owned and must stay valid until the task ends.
Executor.submit[Ctx](entry fn(Ctx*) u64, context Ctx*) !Awaitable[u64, RawTask]:
    ret try this.submitRaw(entry, context)
..

# Releases resources owned by the view. Borrowed adapters may implement this as
# a no-op; it never releases the underlying scheduler.
destr Executor.free() void:
    this.releaseRaw()
..
