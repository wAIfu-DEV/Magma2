mod cpu_impl_win
# Windows processor-count backend used by the portable cpu module.


use "std:win/types" as win
use "std:cast" as cast
use "std:llvm" as ll

# ALL_PROCESSOR_GROUPS. Counting all groups avoids the 64-processor limit of
# GetSystemInfo on large Windows machines.
ext ext_win32_GetActiveProcessorCount GetActiveProcessorCount(groupNumber win.WORD) win.DWORD

global cpuCount u64

cachedCount() u64:
    ret ll.atomicLoadAcquireU64(addrof cpuCount)
..

publishCount(value u64) void:
    ll.atomicStoreReleaseU64(addrof cpuCount, value)
..

pub coreCount() u64:
    count := cachedCount()
    if count != 0: ret count ..
    count = cast.u32to64(ext_win32_GetActiveProcessorCount(0xFFFF))
    if count != 0: publishCount(count) ..
    ret count
..
