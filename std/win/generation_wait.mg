mod generation_wait_win
# Windows generation-counter wait backend used by synchronization APIs.


use "std:win/types" as win
use "std:cast" as cast
use "std:errors" as errors
use "std:llvm" as ll

link "synchronization"

const infinite u32 = 0xFFFFFFFF

pub Wait(
    marker u8
)

ext ext_win32_WaitOnAddress WaitOnAddress(address win.PVOID, compareAddress win.PVOID, addressSize win.SIZE_T, milliseconds win.DWORD) win.BOOL
ext ext_win32_WakeByAddressSingle WakeByAddressSingle(address win.PVOID) void
ext ext_win32_WakeByAddressAll WakeByAddressAll(address win.PVOID) void
ext ext_win32_GetLastError GetLastError() win.DWORD

pub new() !$Wait:
    ret Wait(marker=0)
..

pub observe(generation u32*) u32:
    ret ll.atomicLoadAcquireU32(generation)
..

advance(generation u32*) void:
    ll.atomicFetchAddReleaseU32(generation, 1)
..

pub signal(generation u32*) void:
    advance(generation)
..

pub wait(waiter Wait*, generation u32*, observed u32) !void:
    ok i32 = ext_win32_WaitOnAddress(generation, addrof observed, sizeof u32, infinite)
    if ok == 0:
        throw errors.native(cast.u64to32(ext_win32_GetLastError()), "WaitOnAddress failed")
    ..
..

pub wakeOne(waiter Wait*, generation u32*) void:
    advance(generation)
    ext_win32_WakeByAddressSingle(generation)
..

pub wakeAll(waiter Wait*, generation u32*, count u64) void:
    advance(generation)
    ext_win32_WakeByAddressAll(generation)
..

pub free(waiter Wait*) void:
..
