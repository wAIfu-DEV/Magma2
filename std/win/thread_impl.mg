mod thread_impl_win
# Windows native-thread backend used by the portable thread module.


use "std:win/types" as win
use "std:cast" as cast
use "std:errors" as errors
use "std:context" as context
use "std:heap" as heap

ext ext_win32_CreateThread       CreateThread(attributes win.LPVOID, stackSize win.SIZE_T, startAddress noctx fn(win.LPVOID) u64, parameter win.LPVOID, creationFlags win.DWORD, threadId win.LPVOID) win.HANDLE
ext ext_win32_WaitForSingleObject WaitForSingleObject(handle win.HANDLE, milliseconds win.DWORD) win.DWORD
ext ext_win32_CloseHandle        CloseHandle(handle win.HANDLE) win.BOOL
ext ext_win32_GetLastError       GetLastError() win.DWORD
ext ext_win32_SwitchToThread     SwitchToThread() win.BOOL

pub Thread(
    handle ptr
    launch Launch*
)

Launch(
    entry fn(ptr) u64
    context ptr
    magmaContext context.Ctx
)

noctx threadMain(raw ptr) u64:
    launch Launch*
    unsafe:
        launch = raw
    ..
    ctx = launch.magmaContext
    ret launch.entry(launch.context)
..

pub spawn(entry fn(ptr) u64, context ptr) !$Thread:
    if entry == none:
        throw errors.invalidArgument("thread entry is null")
    ..

    launch Launch* = cast.reinterpret[Launch](try heap.alloc(sizeof Launch))
    onerror:
        unsafe:
            heap.free(launch)
        ..
    ..
    launch.entry = entry
    unsafe:
        launch.context = context
    ..
    launch.magmaContext = ctx
    handle ptr
    unsafe:
        handle = ext_win32_CreateThread(none, 0, threadMain, launch, 0, none)
    ..
    if handle == none:
        code u32 = ext_win32_GetLastError()
        throw errors.native(code, "CreateThread failed")
    ..
    ret Thread(handle=handle, launch=launch)
..

pub isFinished(thread Thread*) !bool:
    if thread.handle == none:
        throw errors.invalidArgument("thread is not joinable")
    ..
    result u32 = ext_win32_WaitForSingleObject(thread.handle, 0)
    if result == 0:
        ret true
    elif result == 258:
        ret false
    elif result == 0xFFFFFFFF:
        throw errors.native(ext_win32_GetLastError(), "thread status query failed")
    ..
    throw errors.failure("unexpected thread status result")
    ret false
..

pub join(thread Thread*) !bool:
    if thread.handle == none:
        throw errors.invalidArgument("thread is not joinable")
    ..

    result u32 = ext_win32_WaitForSingleObject(thread.handle, 0xFFFFFFFF)
    if result == 0xFFFFFFFF:
        waitCode u32 = ext_win32_GetLastError()
        ext_win32_CloseHandle(thread.handle)
        thread.handle = none
        throw errors.native(waitCode, "WaitForSingleObject failed")
    ..
    if result != 0:
        ext_win32_CloseHandle(thread.handle)
        thread.handle = none
        throw errors.failure("unexpected thread wait result")
    ..

    if ext_win32_CloseHandle(thread.handle) == 0:
        closeCode u32 = ext_win32_GetLastError()
        thread.handle = none
        throw errors.native(closeCode, "CloseHandle failed")
    ..
    unsafe:
        heap.free(thread.launch)
    ..
    thread.launch = none
    thread.handle = none
    ret true
..

pub yield() void:
    ext_win32_SwitchToThread()
..
