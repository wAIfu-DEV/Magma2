mod wake
# Portable wait-and-notify primitives for coordinating threads.

use "std:errors" as errors

@platform("windows")
use "std:win/wake_impl" as impl_wake

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/wake_impl" as impl_wake

# A condition variable plus an internal counter.
# Notifications are retained as tokens when no thread is waiting.
# @complexity O(1)
pub condition() u8:
    ret 0
..

# A native counting semaphore.
# @complexity O(1)
pub semaphore() u8:
    ret 1
..

# Owned counted wake primitive safe for notification before or during a wait.
# @warning Do not copy a Wake after it has been shared between threads.
pub Wake(
    impl impl_wake.Wake
)

# Creates a wake primitive using condition() or semaphore().
# @complexity O(1), excluding platform initialization cost
# @throws invalidArgument when strategy is unknown
# @ownership Release with Wake.free after all waiters have stopped.
# @example
#   signal := try wake.new(wake.condition())
pub new(strategy u8) !$Wake:
    if strategy != condition() && strategy != semaphore():
        throw errors.invalidArgument("unknown wake strategy")
    ..
    impl impl_wake.Wake = try impl_wake.new(strategy)
    ret Wake(impl=impl)
..

# Sleeps until a wake token is available, then consumes one token.
# @complexity O(1) when a token is available; otherwise blocks
# @example
#   try signal.wait()
Wake.wait() !void:
    try impl_wake.wait(addrof this.impl)
..

# Adds one wake token and wakes one waiter.
# @complexity O(1), excluding scheduler cost
# @example
#   try signal.notify()
Wake.notify() !void:
    try impl_wake.notify(addrof this.impl)
..

# Releases native synchronization resources.
# @complexity O(1)
# @warning No thread may be waiting or access the Wake after this call.
destr Wake.free() !void:
    try impl_wake.free(addrof this.impl)
..
