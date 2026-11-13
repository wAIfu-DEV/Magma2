mod net_poll
# Allocation-free readiness polling with cross-thread interruption.

use "std:allocator" as allocator
use "std:errors" as errors
use "std:slices" as slices
use "std:net/socket" as socket

@platform("linux", "android")
use "std:linux/net/poll_impl" as impl

@platform("windows")
use "std:win/net/poll_impl" as impl

@platform("darwin", "ios", "freebsd", "netbsd", "openbsd")
use "std:unix/net/poll_impl" as impl

pub const READ u32 = 1
pub const WRITE u32 = 2
pub const ERROR u32 = 4
pub const HANGUP u32 = 8

pub Event(
    token u64
    flags u32
)

pub Poller(
    impl impl.Poller
    capacity u64
    active bool
)

pub new(a allocator.Allocator, capacity u64) !$Poller:
    if capacity == 0:
        throw errors.invalidArgument("poll capacity must be nonzero")
    ..
    native := try impl.new(capacity)
    ret Poller(impl=native, capacity=capacity, active=true)
..

Poller.add(value socket.Socket*, token u64, flags u32) !void:
    if this.active == false:
        throw errors.invalidArgument("poller is closed")
    ..
    handle := try value.nativeHandle()
    try impl.add(addrof this.impl, handle, token, flags)
..

Poller.modify(value socket.Socket*, token u64, flags u32) !void:
    if this.active == false:
        throw errors.invalidArgument("poller is closed")
    ..
    handle := try value.nativeHandle()
    try impl.modify(addrof this.impl, handle, token, flags)
..

Poller.remove(value socket.Socket*) !void:
    if this.active == false:
        throw errors.invalidArgument("poller is closed")
    ..
    handle := try value.nativeHandle()
    try impl.remove(addrof this.impl, handle)
..

# Waits for readiness. timeoutMs < 0 waits indefinitely; zero never blocks.
Poller.wait(output Event[], timeoutMs i64) !u64:
    if this.active == false:
        throw errors.invalidArgument("poller is closed")
    ..
    limit u64 = slices.count(output)
    if limit > this.capacity:
        limit = this.capacity
    ..
    count := try impl.wait(addrof this.impl, limit, timeoutMs)
    for i u64 = 0 to count:
        native := impl.eventAt(addrof this.impl, i)
        # The backend returns no more than the supplied limit.
        bounded i < slices.count(output):
            output[i] = Event(token=native.token, flags=native.flags)
        ..
    ..
    ret count
..

# Interrupts a blocked wait. Safe to call from another thread.
Poller.interrupt() !void:
    if this.active:
        try impl.interrupt(addrof this.impl)
    ..
..

destr Poller.close() !void:
    if this.active:
        try impl.close(addrof this.impl)
        this.active = false
    ..
..
