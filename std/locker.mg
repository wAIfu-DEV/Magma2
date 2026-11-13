mod lock
# Type-erased mutual-exclusion interface with explicit cleanup.

# Type-erased, non-owning handle to a mutual-exclusion implementation.
pub proto Locker(
    lockRaw() !void
    unlockRaw() !void
    releaseRaw() void
)

# Blocks until the caller acquires exclusive access.
# @complexity Implementation-dependent
# @example
#   try guard.lock()
Locker.lock() !void:
    try this.lockRaw()
..

# Releases exclusive access held by the caller.
# @complexity Implementation-dependent
# @warning Unlocking without a matching successful lock is invalid.
# @example
#   try guard.unlock()
Locker.unlock() !void:
    try this.unlockRaw()
..

Locker.do[T](arg T, f fn(T) !void) !void:
    try this.lock()
    defer try this.unlock()
    try f(arg)
..

# Invokes the implementation cleanup callback.
# @complexity Implementation-dependent
# @warning Do not use the Locker after free.
destr Locker.free() void:
    this.releaseRaw()
..
