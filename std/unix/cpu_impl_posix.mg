mod cpu_impl_posix
# POSIX processor-count backend used by the portable cpu module.


use "std:c" as c
use "std:cast" as cast
use "std:llvm" as ll

ext ext_sysconf sysconf(name c.int) c.long

global cpuCount u64

cachedCount() u64:
    ret ll.atomicLoadAcquireU64(addrof cpuCount)
..

publishCount(value u64) void:
    ll.atomicStoreReleaseU64(addrof cpuCount, value)
..

pub coreCount() u64:
    cached := cachedCount()
    if cached != 0: ret cached ..
    count i64 = ext_sysconf(58)
    if count < 1:
        ret 0
    ..
    cached = cast.itou(count)
    publishCount(cached)
    ret cached
..
