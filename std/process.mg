mod process
# Starts, waits for, and asynchronously executes child processes.

use "std:allocator" as allocator
use "std:future" as future
use "std:thread_pool" as thread_pool
use "std:abort" as abort
use "std:time" as time

@platform("windows")
use "std:win/process_impl" as impl_process

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/process_impl" as impl_process

# A spawned child process. A Process owns its native process resource and must
# be waited exactly once.
pub Process(
    impl impl_process.Process
)

SpawnTask(
    executable str
    arguments str[]
    external abort.Signal
    hasExternal bool
)

# Starts executable with arguments. The executable becomes argv[0], so callers
# should not repeat it in arguments. The child inherits the parent's environment
# and standard streams.
# @param executable executable path or name
# @param arguments arguments following argv[0]
# @returns owned running process handle
# @mustcall await or kill
# @example
#   child := try process.spawn("tool", arguments)
#   exitCode := try child.await()
pub spawn(executable str, arguments str[]) !$Process:
    child := try impl_process.spawn(executable, arguments)
    ret Process(impl=move child)
..

# Starts a process with a complete replacement environment. Each entry uses
# native name=value form. An empty slice creates an empty child environment.
pub spawnWithEnv(executable str, arguments str[], environment str[]) !$Process:
    child := try impl_process.spawnWithEnv(executable, arguments, environment)
    ret Process(impl=move child)
..

# Returns true when the child has exited. This does not release the Process;
# await must still be called afterwards.
# @example
#   finished := try child.isFinished()
Process.isFinished() !bool:
    ret try impl_process.isFinished(addrof this.impl)
..

# Waits for the child, releases its native resource, and returns its exit code.
# On Unix, signal termination is reported as 128 plus the signal number.
# @returns child exit code
# @ownership Consumes the process handle.
destr Process.await() !u32:
    ret try impl_process.await(addrof this.impl)
..

# Terminates the child if it is still running and releases its native resource.
# No exit code is returned. Use await when normal completion matters.
# @ownership Consumes the process handle.
destr Process.kill() !void:
    try impl_process.kill(addrof this.impl)
..

# Starts executable, waits for it to finish, and returns its exit code.
# @param executable executable path or name
# @param arguments arguments following argv[0]
# @returns child exit code
# @example
#   exitCode := try process.exec("tool", arguments)
pub exec(executable str, arguments str[]) !u32:
    child := try spawn(executable, arguments)
    ret try child.await()
..

checkSignals(task SpawnTask*, signal abort.Signal) !bool:
    try signal.check()
    if task.hasExternal: try task.external.check() ..
    ret true
..

runExecTask(task SpawnTask*, signal abort.Signal) !u32:
    try checkSignals(task, signal)
    child := try spawn(task.executable, task.arguments)
    finished bool, pollError error = child.isFinished()
    if pollError.nok():
        child.kill()
        throw pollError
    ..
    loop finished == false:
        checked bool, abortError error = checkSignals(task, signal)
        if abortError.nok():
            child.kill()
            throw abortError
        ..
        time.sleep(5)
        nextFinished bool, nextError error = child.isFinished()
        if nextError.nok():
            child.kill()
            throw nextError
        ..
        finished = nextFinished
    ..
    ret try child.await()
..

# Runs exec on the supplied pool and resolves to the child's exit code. The
# executable and argument slice are borrowed and must remain valid until await.
# @param pool pool used to run the blocking process operation
# @param a allocator for future state
# @param executable executable path or name
# @param arguments arguments following argv[0]
# @returns owned future resolving to the child exit code
# @ownership The future must be awaited or freed according to the future API.
# @example
#   pending := try process.execAsync(pool, a, "tool", arguments)
pub execAsync(executable str, arguments str[]) !$future.Future[u32]:
    task := SpawnTask(executable=executable, arguments=arguments, external=abort.Signal(state=none), hasExternal=false)
    ret try future.newAbort[u32, SpawnTask](ctx.exec, runExecTask, task)
..

# Executes a process asynchronously while observing a caller-owned signal.
pub execAsyncAbort(executable str, arguments str[], signal abort.Signal) !$future.Future[u32]:
    task := SpawnTask(executable=executable, arguments=arguments, external=signal, hasExternal=true)
    ret try future.newAbort[u32, SpawnTask](ctx.exec, runExecTask, task)
..
