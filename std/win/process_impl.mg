mod process_impl_win
# Windows child-process backend used by the portable process module.


use "std:win/types" as win
use "std:allocator" as allocator
use "std:heap" as heap
use "std:strings" as strings
use "std:slices" as slices
use "std:utf8" as utf8
use "std:errors" as errors
use "std:cast" as cast
use "std:memory" as memory
use "std:checked" as checked
use "std:utf16" as utf16

ext ext_win32_CreateProcessW CreateProcessW(applicationName win.LPCWSTR, commandLineValue win.LPWSTR, processAttributes win.LPVOID, threadAttributes win.LPVOID, inheritHandles win.BOOL, creationFlags win.DWORD, environment win.LPVOID, currentDirectory win.LPCWSTR, startupInfo win.LPVOID, processInformation win.LPVOID) win.BOOL
ext ext_win32_WaitForSingleObject WaitForSingleObject(handle win.HANDLE, milliseconds win.DWORD) win.DWORD
ext ext_win32_GetExitCodeProcess GetExitCodeProcess(handle win.HANDLE, exitCode win.DWORD*) win.BOOL
ext ext_win32_TerminateProcess TerminateProcess(handle win.HANDLE, exitCode win.UINT) win.BOOL
ext ext_win32_CloseHandle CloseHandle(handle win.HANDLE) win.BOOL
ext ext_win32_GetLastError GetLastError() win.DWORD

StartupInfo(
    cb u32
    reserved ptr
    desktop ptr
    title ptr
    x u32
    y u32
    xSize u32
    ySize u32
    xCountChars u32
    yCountChars u32
    fillAttribute u32
    flags u32
    showWindow u16
    reserved2Bytes u16
    reserved2 u8*
    stdInput ptr
    stdOutput ptr
    stdError ptr
)

ProcessInformation(
    process ptr
    thread ptr
    processId u32
    threadId u32
)

pub Process(
    handle ptr
)

containsNull(value str) bool:
    for i u64 = 0 to value.countBytes():
        if strings.byteAt(value, i) == 0:
            ret true
        ..
    ..
    ret false
..

# Appends one argument using the CommandLineToArgvW quoting rules. The output
# allocation is deliberately sized for the worst case (every byte a slash).
appendQuoted(value str, out u8*, offset u64*) void:
    out[*offset] = 34
    *offset = *offset + 1
    slashes u64 = 0
    for i u64 = 0 to value.countBytes():
        byte u8 = strings.byteAt(value, i)
        if byte == 92:
            slashes = slashes + 1
        elif byte == 34:
            loop slashes > 0:
                out[*offset] = 92
                *offset = *offset + 1
                out[*offset] = 92
                *offset = *offset + 1
                slashes = slashes - 1
            ..
            out[*offset] = 92
            *offset = *offset + 1
            out[*offset] = 34
            *offset = *offset + 1
        else:
            loop slashes > 0:
                out[*offset] = 92
                *offset = *offset + 1
                slashes = slashes - 1
            ..
            out[*offset] = byte
            *offset = *offset + 1
        ..
    ..
    loop slashes > 0:
        out[*offset] = 92
        *offset = *offset + 1
        out[*offset] = 92
        *offset = *offset + 1
        slashes = slashes - 1
    ..
    out[*offset] = 34
    *offset = *offset + 1
..

commandLine(a allocator.Allocator, executable str, arguments str[]) !$str:
    count u64 = slices.count(arguments)
    total u64 = executable.countBytes()
    for i u64 = 0 to count:
        n u64 = arguments[i].countBytes()
        if n > (0 - 1 - total):
            throw errors.wouldOverflow("process command line is too large")
        ..
        total = total + n
    ..
    if total > ((0 - 1 - ((count + 1) * 3)) / 2):
        throw errors.wouldOverflow("process command line is too large")
    ..
    capacity u64 = (total * 2) + ((count + 1) * 3)
    data u8* = try a.alloc(capacity + 1)
    offset u64 = 0
    appendQuoted(executable, data, addrof offset)
    for i u64 = 0 to count:
        data[offset] = 32
        offset = offset + 1
        appendQuoted(arguments[i], data, addrof offset)
    ..
    data[offset] = 0
    ret strings.fromPtrNoCopy(data, offset)
..

pub spawn(executable str, arguments str[]) !$Process:
    if executable.countBytes() == 0 || containsNull(executable):
        throw errors.invalidArgument("process executable is empty or contains a null byte")
    ..
    for i u64 = 0 to slices.count(arguments):
        if containsNull(arguments[i]):
            throw errors.invalidArgument("process argument contains a null byte")
        ..
    ..

    a := heap.allocator()
    line str = try commandLine(a, executable, arguments)
    defer line.free()
    
    line16 u16[] = try utf8.utf8To16NT(line)
    defer a.free(slices.toPtr(line16))

    startup StartupInfo
    startup.cb = cast.u64to32(sizeof StartupInfo)
    information ProcessInformation
    # A null application name makes CreateProcess search the usual executable
    # locations while taking argv[0] from the quoted command line.
    ok win.BOOL = ext_win32_CreateProcessW(none, slices.toPtr(line16), none, none, 1, 0, none, none, addrof startup, addrof information)
    if ok == 0:
        throw errors.native(ext_win32_GetLastError(), "CreateProcessW failed")
    ..
    onerror ext_win32_CloseHandle(information.process)
    if ext_win32_CloseHandle(information.thread) == 0:
        code u32 = ext_win32_GetLastError()
        throw errors.native(code, "CloseHandle failed for process thread")
    ..
    ret Process(handle=information.process)
..

environmentBlock(a allocator.Allocator, entries str[]) !$u16*:
    count := slices.count(entries)
    total u64 = 1
    for i u64 = 0 to count:
        total = try checked.uAdd(total, try utf16.fromUtf8Size(entries[i]))
        total = try checked.uAdd(total, 1)
    ..
    block := try a.allocT[u16](total)
    offset u64 = 0
    onerror a.free(block)
    for i u64 = 0 to count:
        encoded u16[] = try utf8.utf8To16(a, entries[i])
        units := slices.count(encoded)
        memory.copy(slices.toPtr(encoded), addrof block[offset], units * sizeof u16)
        a.free(slices.toPtr(encoded))
        offset = offset + units
        block[offset] = 0
        offset = offset + 1
    ..
    block[offset] = 0
    ret block
..

pub spawnWithEnv(executable str, arguments str[], environment str[]) !$Process:
    if executable.countBytes() == 0 || containsNull(executable):
        throw errors.invalidArgument("process executable is empty or contains a null byte")
    ..
    a := heap.allocator()
    line := try commandLine(a, executable, arguments)
    defer line.free()
    line16 := try utf8.utf8To16NT(line)
    defer a.free(slices.toPtr(line16))
    block := try environmentBlock(a, environment)
    defer a.free(block)
    startup StartupInfo
    startup.cb = cast.u64to32(sizeof StartupInfo)
    information ProcessInformation
    ok := ext_win32_CreateProcessW(none, slices.toPtr(line16), none, none, 1, 0x400, block, none, addrof startup, addrof information)
    if ok == 0: throw errors.native(ext_win32_GetLastError(), "CreateProcessW failed") ..
    ext_win32_CloseHandle(information.thread)
    ret Process(handle=information.process)
..

pub isFinished(process Process*) !bool:
    if process.handle == none:
        throw errors.invalidArgument("process has already been waited")
    ..
    result u32 = ext_win32_WaitForSingleObject(process.handle, 0)
    if result == 0:
        ret true
    elif result == 258:
        ret false
    elif result == 0xFFFFFFFF:
        throw errors.native(ext_win32_GetLastError(), "process status query failed")
    ..
    throw errors.failure("unexpected process wait result")
    ret false
..

pub await(process Process*) !u32:
    if process.handle == none:
        throw errors.invalidArgument("process has already been waited")
    ..
    result u32 = ext_win32_WaitForSingleObject(process.handle, 0xFFFFFFFF)
    if result != 0:
        if result == 0xFFFFFFFF:
            throw errors.native(ext_win32_GetLastError(), "process wait failed")
        ..
        throw errors.failure("unexpected process wait result")
    ..
    exitCode u32 = 0
    if ext_win32_GetExitCodeProcess(process.handle, addrof exitCode) == 0:
        throw errors.native(ext_win32_GetLastError(), "GetExitCodeProcess failed")
    ..
    if ext_win32_CloseHandle(process.handle) == 0:
        code u32 = ext_win32_GetLastError()
        process.handle = none
        throw errors.native(code, "CloseHandle failed for process")
    ..
    process.handle = none
    ret exitCode
..

pub kill(process Process*) !void:
    if process.handle == none:
        throw errors.invalidArgument("process has already been consumed")
    ..

    status u32 = ext_win32_WaitForSingleObject(process.handle, 0)
    if status == 258:
        if ext_win32_TerminateProcess(process.handle, 1) == 0:
            throw errors.native(ext_win32_GetLastError(), "TerminateProcess failed")
        ..
        status = ext_win32_WaitForSingleObject(process.handle, 0xFFFFFFFF)
    ..
    if status == 0xFFFFFFFF:
        throw errors.native(ext_win32_GetLastError(), "process wait after kill failed")
    elif status != 0:
        throw errors.failure("unexpected process wait result after kill")
    ..

    if ext_win32_CloseHandle(process.handle) == 0:
        code u32 = ext_win32_GetLastError()
        process.handle = none
        throw errors.native(code, "CloseHandle failed for process")
    ..
    process.handle = none
..
