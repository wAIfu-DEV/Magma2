mod net_socket
# Owned portable stream and datagram sockets.

use "std:net/address" as address
use "std:errors" as errors
use "std:reader" as reader
use "std:writer" as writer
use "std:duplex" as duplex
use "std:slices" as slices

@platform("windows")
use "std:win/net/socket_impl" as impl

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/net/socket_impl" as impl

pub const TYPE_STREAM u8 = 1
pub const TYPE_DATAGRAM u8 = 2
pub const SHUTDOWN_READ u8 = 1
pub const SHUTDOWN_WRITE u8 = 2
pub const SHUTDOWN_BOTH u8 = 3

pub Socket impl reader.Reader writer.Writer duplex.Duplex(
    handle ptr
    family u8
    kind u8
    open bool
)

pub Received(
    count u64
    source address.Endpoint
)

pub open(family u8, kind u8) !$Socket:
    if family != address.FAMILY_IPV4 && family != address.FAMILY_IPV6:
        throw errors.invalidArgument("unsupported socket family")
    ..
    if kind != TYPE_STREAM && kind != TYPE_DATAGRAM:
        throw errors.invalidArgument("unsupported socket type")
    ..
    handle := try impl.openBlocking(family, kind)
    ret Socket(handle=handle, family=family, kind=kind, open=true)
..

pub openNonBlocking(family u8, kind u8) !$Socket:
    if family != address.FAMILY_IPV4 && family != address.FAMILY_IPV6:
        throw errors.invalidArgument("unsupported socket family")
    ..
    if kind != TYPE_STREAM && kind != TYPE_DATAGRAM:
        throw errors.invalidArgument("unsupported socket type")
    ..
    handle := try impl.openNonBlocking(family, kind)
    ret Socket(handle=handle, family=family, kind=kind, open=true)
..

Socket.requireOpen() !void:
    if this.open == false:
        throw errors.invalidArgument("socket is closed")
    ..
..

Socket.bind(endpoint address.Endpoint) !void:
    try this.requireOpen()
    try impl.bind(this.handle, endpoint)
..

Socket.listen(backlog u32) !void:
    try this.requireOpen()
    if this.kind != TYPE_STREAM:
        throw errors.invalidArgument("listen requires a stream socket")
    ..
    try impl.listen(this.handle, backlog)
..

Socket.accept() !$Socket:
    try this.requireOpen()
    handle ptr, failure error = impl.acceptBlocking(this.handle)
    if failure.nok():
        throw failure
    ..
    ret Socket(handle=handle, family=this.family, kind=TYPE_STREAM, open=true)
..

Socket.acceptNonBlocking() !$Socket:
    try this.requireOpen()
    handle ptr, failure error = impl.acceptNonBlocking(this.handle)
    if failure.nok(): throw failure ..
    ret Socket(handle=handle, family=this.family, kind=TYPE_STREAM, open=true)
..

Socket.connect(endpoint address.Endpoint) !void:
    try this.requireOpen()
    try impl.connect(this.handle, endpoint)
..

Socket.setNonBlocking(enabled bool) !void:
    try this.requireOpen()
    try impl.setNonBlocking(this.handle, enabled)
..

Socket.setReuseAddress(enabled bool) !void:
    try this.requireOpen()
    try impl.setReuseAddress(this.handle, enabled)
..

Socket.localEndpoint() !address.Endpoint:
    try this.requireOpen()
    ret try impl.localEndpoint(this.handle)
..

Socket.peerEndpoint() !address.Endpoint:
    try this.requireOpen()
    ret try impl.peerEndpoint(this.handle)
..

Socket.recv(buffer u8[], count u64) !u64:
    try this.requireOpen()
    if count > slices.count(buffer):
        throw errors.invalidArgument("receive count exceeds buffer length")
    ..
    received := try impl.recv(this.handle, buffer, count)
    if received > count:
        throw errors.failure("socket received more bytes than requested")
    ..
    ret received
..

Socket.send(bytes str) !u64:
    try this.requireOpen()
    ret try impl.send(this.handle, bytes)
..

Socket.recvFrom(buffer u8[], count u64) !Received:
    try this.requireOpen()
    if count > slices.count(buffer):
        throw errors.invalidArgument("receive count exceeds buffer length")
    ..
    source address.Endpoint
    received u64 = try impl.recvFrom(this.handle, buffer, count, addrof source)
    if received > count:
        throw errors.failure("socket received more bytes than requested")
    ..
    ret Received(count=received, source=source)
..

Socket.sendTo(bytes str, endpoint address.Endpoint) !u64:
    try this.requireOpen()
    ret try impl.sendTo(this.handle, bytes, endpoint)
..

Socket.shutdown(direction u8) !void:
    try this.requireOpen()
    try impl.shutdown(this.handle, direction)
..

destr Socket.close() !void:
    if this.open:
        try impl.close(this.handle)
        this.open = false
        this.handle = none
    ..
..

socketRead(raw ptr, buffer u8[], count u64) !u64:
    # SAFETY: Socket.reader stores its live receiver as the callback context.
    unsafe:
        socket Socket* = raw
        ret try socket.recv(buffer, count)
    ..
..

socketWrite(raw ptr, bytes str) !u64:
    # SAFETY: Socket.writer stores its live receiver as the callback context.
    unsafe:
        socket Socket* = raw
        ret try socket.send(bytes)
    ..
..

Socket.readRaw(buffer u8[], count u64) !u64:
    ret try this.recv(buffer, count)
..

Socket.write(bytes str) !u64:
    ret try this.send(bytes)
..

Socket.reader() !reader.Reader:
    try this.requireOpen()
    ret this.protoBorrow()
..

Socket.writer() !writer.Writer:
    try this.requireOpen()
    ret this.protoBorrow()
..

Socket.duplex() !duplex.Duplex:
    try this.requireOpen()
    ret this.protoBorrow()
..

Socket.nativeHandle() !ptr:
    try this.requireOpen()
    ret this.handle
..
