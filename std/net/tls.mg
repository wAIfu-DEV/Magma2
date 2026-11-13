mod net_tls
# Nonblocking client-side TLS over a connected std/net socket.

use "std:allocator" as allocator
use "std:net/socket" as socket
use "std:errors" as errors
use "std:slices" as slices

@platform("linux")
use "std:linux/net/tls_impl" as impl

@platform("windows")
use "std:win/net/tls_impl" as impl

@platform("android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:net/tls_unsupported" as impl

pub const WANT_NONE u8 = 0
pub const WANT_READ u8 = 1
pub const WANT_WRITE u8 = 2

pub Context(
    native ptr
    active bool
)

pub Session(
    native ptr
    want u8
    handshaken bool
    active bool
)

pub newContext() !$Context:
    native := try impl.newContext()
    ret Context(native=native, active=true)
..

Context.open(transport socket.Socket*, host str) !$Session:
    a := ctx.alloc
    if this.active == false:
        throw impl.closedContextError()
    ..
    native := try impl.open(this.native, transport, host)
    ret Session(native=native, want=WANT_WRITE, handshaken=false, active=true)
..

Session.handshake() !bool:
    result := try impl.handshake(this.native)
    this.want = result.want
    this.handshaken = result.complete
    ret result.complete
..

Session.send(bytes str) !u64:
    result := try impl.send(this.native, bytes)
    this.want = result.want
    ret result.count
..

Session.recv(buffer u8[], count u64) !u64:
    if count > slices.count(buffer):
        throw errors.invalidArgument("receive count exceeds buffer length")
    ..
    result := try impl.recv(this.native, buffer, count)
    if result.count > count:
        throw errors.failure("TLS received more bytes than requested")
    ..
    this.want = result.want
    ret result.count
..

destr Session.close() !void:
    if this.active:
        try impl.close(this.native)
        this.native = none
        this.active = false
    ..
..

destr Context.close() !void:
    if this.active:
        try impl.closeContext(this.native)
        this.native = none
        this.active = false
    ..
..
