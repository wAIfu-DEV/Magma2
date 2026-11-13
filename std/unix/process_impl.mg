mod process_impl_unix
# Unix child-process backend used by the portable process module.


use "std:c" as c
use "std:heap" as heap
use "std:strings" as strings
use "std:slices" as slices
use "std:errors" as errors
use "std:cast" as cast
use "std:checked" as checked

ext ext_unix_fork fork() c.int
ext ext_unix_execvp execvp(file u8*, arguments ptr) c.int
ext ext_unix_execve execve(file u8*, arguments ptr, environment ptr) c.int
ext ext_unix_waitpid waitpid(pid c.int, status c.int*, options c.int) c.int
ext ext_unix_kill kill(pid c.int, signal c.int) c.int
ext ext_unix_exit _exit(status c.int) void

pub Process(
    pid i32
    finished bool
    exitCode u32
)

containsNull(value str) bool:
    for i u64 = 0 to value.countBytes():
        if strings.byteAt(value, i) == 0:
            ret true
        ..
    ..
    ret false
..

decodeStatus(status i32) u32:
    raw u64 = cast.itou(cast.i32to64(status))
    signal u32 = cast.u64to32(raw & 127)
    if signal == 0:
        ret cast.u64to32((raw >> 8) & 255)
    ..
    ret 128 + signal
..

freeArguments(argv u8**, count u64) void:
    # SAFETY: argv contains count initialized owned C-string pointers followed
    # by storage allocated from the same allocator.
    unsafe:
    a := heap.allocator()
    for i u64 = 0 to count:
        a.free(argv[i])
    ..
      a.free(argv)
    ..
..

pub spawn(executable str, arguments str[]) !$Process:
    # SAFETY: argv is allocated for count + 2 entries; initialized tracks the
    # owned prefix and the final slot is reserved for the null terminator.
    unsafe:
    if executable.countBytes() == 0 || containsNull(executable):
        throw errors.invalidArgument("process executable is empty or contains a null byte")
    ..
    count u64 = slices.count(arguments)
    for i u64 = 0 to count:
        if containsNull(arguments[i]):
            throw errors.invalidArgument("process argument contains a null byte")
        ..
    ..

    a := heap.allocator()
    argvCount := try checked.uAdd(count, 2)
    argv u8** = try a.allocT[u8*](argvCount)
    initialized u64 = 0
    onerror freeArguments(argv, initialized)
    executableCopy u8* = try strings.toCstr(executable)
    argv[0] = executableCopy
    initialized = 1
    for i u64 = 0 to count:
        copied u8*, copyError error = strings.toCstr(arguments[i])
        if copyError.nok():
            throw copyError
        ..
        argv[i + 1] = copied
        initialized = initialized + 1
    ..
    argv[count + 1] = none

    pid i32 = ext_unix_fork()
    if pid == 0:
        ext_unix_execvp(executableCopy, argv)
        ext_unix_exit(127)
    ..
    freeArguments(argv, initialized)
    if pid < 0:
        throw errors.failure("fork failed")
    ..
      ret Process(pid=pid, finished=false, exitCode=0)
    ..
..

pub spawnWithEnv(executable str, arguments str[], environment str[]) !$Process:
    # SAFETY: argv/envp allocations include their terminator slots and their
    # initialized counters precisely track owned C strings for cleanup.
    unsafe:
    if executable.countBytes() == 0 || containsNull(executable):
        throw errors.invalidArgument("process executable is empty or contains a null byte")
    ..
    a := heap.allocator()
    count := slices.count(arguments)
    argvCount := try checked.uAdd(count, 2)
    argv := try a.allocT[u8*](argvCount)
    initialized u64 = 0
    onerror freeArguments(argv, initialized)
    executableCopy := try strings.toCstr(executable)
    argv[0] = executableCopy
    initialized = 1
    for i u64 = 0 to count:
        argv[i + 1] = try strings.toCstr(arguments[i])
        initialized = initialized + 1
    ..
    argv[count + 1] = none
    environmentCount := slices.count(environment)
    envpCount := try checked.uAdd(environmentCount, 1)
    envp := try a.allocT[u8*](envpCount)
    envInitialized u64 = 0
    onerror freeArguments(envp, envInitialized)
    for i u64 = 0 to environmentCount:
        envp[i] = try strings.toCstr(environment[i])
        envInitialized = envInitialized + 1
    ..
    envp[environmentCount] = none
    pid := ext_unix_fork()
    if pid == 0:
        ext_unix_execve(executableCopy, argv, envp)
        ext_unix_exit(127)
    ..
    freeArguments(argv, initialized)
    freeArguments(envp, envInitialized)
    if pid < 0: throw errors.failure("fork failed") ..
      ret Process(pid=pid, finished=false, exitCode=0)
    ..
..

pub isFinished(process Process*) !bool:
    if process.pid == 0:
        throw errors.invalidArgument("process has already been waited")
    ..
    if process.finished:
        ret true
    ..
    status i32 = 0
    result i32 = ext_unix_waitpid(process.pid, addrof status, 1)
    if result < 0:
        throw errors.failure("waitpid failed")
    elif result == 0:
        ret false
    ..
    process.exitCode = decodeStatus(status)
    process.finished = true
    ret true
..

pub await(process Process*) !u32:
    if process.pid == 0:
        throw errors.invalidArgument("process has already been waited")
    ..
    if process.finished == false:
        status i32 = 0
        result i32 = ext_unix_waitpid(process.pid, addrof status, 0)
        if result < 0:
            throw errors.failure("waitpid failed")
        ..
        process.exitCode = decodeStatus(status)
    ..
    code u32 = process.exitCode
    process.pid = 0
    process.finished = true
    ret code
..

pub kill(process Process*) !void:
    if process.pid == 0:
        throw errors.invalidArgument("process has already been consumed")
    ..
    if process.finished == false:
        if ext_unix_kill(process.pid, 9) != 0:
            throw errors.failure("kill failed")
        ..
        status i32 = 0
        if ext_unix_waitpid(process.pid, addrof status, 0) < 0:
            throw errors.failure("waitpid after kill failed")
        ..
    ..
    process.pid = 0
    process.finished = true
..
