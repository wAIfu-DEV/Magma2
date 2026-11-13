mod adaptive_spinlock
# Adaptive TTAS lock optimized for very short critical sections.

use "std:atomic" as atomic
use "std:locker" as locker
use "std:llvm" as ll

@platform("windows")
use "std:win/thread_impl" as thread_impl

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/thread_impl" as thread_impl

pub AdaptiveSpinLock impl locker.Locker(
    state atomic.U32
)

compareExchange(value atomic.U32*, expected u32, desired u32) u32:
    ret ll.atomicCompareExchangeAcquireU32(value, expected, desired)
..

loadRelaxed(value atomic.U32*) u32:
    ret ll.atomicLoadRelaxedU32(value)
..

storeRelease(value atomic.U32*, desired u32) void:
    ll.atomicStoreReleaseU32(value, desired)
..

cpuRelax() void:
    ll.pause()
..

lockSlow(value AdaptiveSpinLock*) void:
    loop true:
        for spin u64 = 0 to 64:
            if loadRelaxed(addrof value.state) == 0:
                if compareExchange(addrof value.state, 0, 1) == 0:
                    ret
                ..
            ..
            cpuRelax()
        ..
        thread_impl.yield()
    ..
..

pub new() AdaptiveSpinLock:
    ret AdaptiveSpinLock(state=atomic.newU32(0))
..

AdaptiveSpinLock.lock() void:
    if compareExchange(addrof this.state, 0, 1) == 0:
        ret
    ..
    lockSlow(this)
..

AdaptiveSpinLock.unlock() void:
    storeRelease(addrof this.state, 0)
..

AdaptiveSpinLock.lockRaw() !void:
    this.lock()
..

AdaptiveSpinLock.unlockRaw() !void:
    this.unlock()
..

AdaptiveSpinLock.releaseRaw() void:
..

AdaptiveSpinLock.locker() locker.Locker:
    ret this.protoBorrow()
..
