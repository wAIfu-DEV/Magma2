mod spinlock
# Portable spin-based mutual exclusion for very short critical sections.
# @warning Prefer a mutex when lock contention or wait duration may be significant.

# Implementation from the 2026 talk "Lock free programming is dead, long live lock free programming"
# By Fedor Pikus at C++now https://www.youtube.com/watch?v=UdKqfQ3a_sY

use "std:atomic" as atomic
use "std:locker" as locker

@platform("windows")
use "std:win/thread_impl" as impl_thread

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/thread_impl" as impl_thread

# Busy-waiting lock intended only for very short, non-blocking critical sections.
# @warning Do not copy a SpinLock after sharing it between threads.
pub SpinLock impl locker.Locker(
    flag atomic.U64
)

# Creates an unlocked spin lock.
# @complexity O(1)
# @example
#   guard := spinlock.new()
pub new() SpinLock:
    ret SpinLock(
        flag = atomic.newU64(1)
    )
..

# Spins and yields until exclusive access is acquired.
# @complexity O(1) when uncontended; unbounded while another thread holds the lock
# @warning Never hold this lock while performing blocking or long-running work.
# @example
#   guard.lock()
SpinLock.lock() void:
    loop this.flag.load() == 0 || this.flag.exchange(0) == 0:
        impl_thread.yield()
    ..
..

# Releases exclusive access.
# @complexity O(1)
# @warning The caller must hold the lock.
SpinLock.unlock() void:
    this.flag.store(1)
..

SpinLock.lockRaw() !void:
    this.lock()
..

SpinLock.unlockRaw() !void:
    this.unlock()
..

SpinLock.releaseRaw() void:
..

# Returns a non-owning type-erased view of this spin lock.
# @complexity O(1)
# @ownership The SpinLock must outlive the returned Locker.
SpinLock.locker() locker.Locker:
    ret this.protoBorrow()
..
