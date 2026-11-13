mod read_write_lock
# Reader-writer spin lock encoded in one atomic word.

use "std:atomic" as atomic
use "std:llvm" as ll

@platform("windows")
use "std:win/thread_impl" as thread_impl

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/thread_impl" as thread_impl

const WRITER_BIT u32 = 2147483648
const READER_MASK u32 = 2147483647
const SPIN_COUNT u64 = 64

# Atomic compare-and-exchange returning the value observed before the operation.
compareExchange(value atomic.U32*, expected u32, desired u32) u32:
    ret ll.atomicCompareExchangeAcquireU32(value, expected, desired)
..

pause() void:
    ll.pause()
..

yieldThread() void:
    thread_impl.yield()
..

# Spin briefly before yielding the processor to reduce contention overhead.
waitTurn(spins u64) void:
    if spins < SPIN_COUNT:
        pause()
    else:
        yieldThread()
    ..
..

# Reader-writer spin lock. Zero means unlocked, WRITER_BIT means write-locked,
# and a positive value below WRITER_BIT is the number of active readers.
# Multiple readers may hold the lock together; a writer holds it exclusively.
# This lock is not writer-fair, and must not be copied after it is shared.
pub ReadWriteLock(
    state atomic.U32
)

# Creates an unlocked reader-writer lock.
pub new() ReadWriteLock:
    ret ReadWriteLock(state=atomic.newU32(0))
..

# Acquires shared read access, waiting while a writer holds the lock.
# @warning Pair with exactly one unlockRead call on the acquiring thread.
ReadWriteLock.readLock() void:
    spins u64 = 0
    loop true:
        observed := this.state.loadAcquire()
        if (observed & WRITER_BIT) == 0 && observed < READER_MASK:
            if compareExchange(addrof this.state, observed, observed + 1) == observed:
                ret
            ..
        ..
        waitTurn(spins)
        if spins < SPIN_COUNT:
            spins = spins + 1
        ..
    ..
..

# Releases shared read access.
# @warning The current thread must hold one read lock.
ReadWriteLock.readUnlock() void:
    this.state.fetchSubAcqRel(1)
..

# Acquires exclusive write access, waiting until all readers leave.
# @warning Pair with exactly one unlockWrite call on the acquiring thread.
ReadWriteLock.writeLock() void:
    spins u64 = 0
    loop true:
        if compareExchange(addrof this.state, 0, WRITER_BIT) == 0:
            ret
        ..
        waitTurn(spins)
        if spins < SPIN_COUNT:
            spins = spins + 1
        ..
    ..
..

# Releases exclusive write access.
# @warning The current thread must hold the write lock.
ReadWriteLock.writeUnlock() void:
    this.state.storeRelease(0)
..
