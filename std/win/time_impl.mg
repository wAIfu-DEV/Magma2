mod time_impl_win
# Windows clock backend used by the portable time module.


use "std:win/types" as win
use "std:errors" as err
use "std:cast" as cast
use "std:llvm" as ll

ext ext_win32_QueryPerformanceCounter        QueryPerformanceCounter(value win.LONGLONG*) win.BOOL
ext ext_win32_QueryPerformanceFrequency      QueryPerformanceFrequency(value win.LONGLONG*) win.BOOL
ext ext_win32_GetSystemTimePreciseAsFileTime GetSystemTimePreciseAsFileTime(value FileTime*) void
ext ext_win32_Sleep                          Sleep(dwMilliseconds win.DWORD) void
ext ext_win32_GetCurrentProcess              GetCurrentProcess() win.HANDLE
ext ext_win32_GetProcessTimes                GetProcessTimes(process win.HANDLE, creation FileTime*, exit FileTime*, kernel FileTime*, user FileTime*) win.BOOL

FileTime(
    lowDateTime u32,
    highDateTime u32,
)

global tickFrequency u64

loadTickFrequency() u64:
    ret ll.atomicLoadAcquireU64(addrof tickFrequency)
..

publishTickFrequency(value u64) void:
    ll.atomicStoreReleaseU64(addrof tickFrequency, value)
..

fileTimeValue(value FileTime*) u64:
    high u64 = cast.u32to64(value.highDateTime) << 32
    ret high | cast.u32to64(value.lowDateTime)
..

pub processCpuTimeNs() u64:
    creation FileTime
    exit FileTime
    kernel FileTime
    user FileTime
    # GetCurrentProcess returns the constant pseudo-handle -1. Supplying it
    # directly avoids a foreign call while preserving the same semantics.
    currentProcess win.HANDLE = cast.utop(cast.itou(-1))
    ok i32 = ext_win32_GetProcessTimes(currentProcess, addrof creation, addrof exit, addrof kernel, addrof user)
    if ok == 0:
        ret 0
    ..
    # FILETIME uses 100-nanosecond intervals.
    ret (fileTimeValue(addrof kernel) + fileTimeValue(addrof user)) * 100
..

pub ticks() u64:
    t u64
    ext_win32_QueryPerformanceCounter(addrof t)
    ret t
..

pub tickFrequency() u64:
    frequency := loadTickFrequency()
    if frequency != 0:
        ret frequency
    ..
    ext_win32_QueryPerformanceFrequency(addrof frequency)
    if frequency != 0: publishTickFrequency(frequency) ..
    ret frequency
..

unixEpochIntervals() u64:
    value := FileTime(lowDateTime=0, highDateTime=0)
    ext_win32_GetSystemTimePreciseAsFileTime(addrof value)

    high u64 = cast.u32to64(value.highDateTime) << 32
    low u64 = cast.u32to64(value.lowDateTime)
    intervals u64 = high | low
    ret intervals - 116444736000000000
..

# Windows system time is measured in 100 ns intervals since 1601-01-01.
pub unixTimestamp() u64:
    ret unixEpochIntervals() / 10000000
..

pub unixTimestampMs() u64:
    ret unixEpochIntervals() / 10000
..

pub unixTimestampUs() u128:
    intervals u128 = cast.u64to128(unixEpochIntervals())
    ret intervals / 10
..

pub unixTimestampNs() u128:
    intervals u128 = cast.u64to128(unixEpochIntervals())
    ret intervals * 100
..

pub sleep(ms u64) void:
    ext_win32_Sleep(cast.u64to32(ms))
..
