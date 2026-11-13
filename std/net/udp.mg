mod net_udp
# UDP datagram sockets.

use "std:net/address" as address
use "std:net/socket" as socket

pub Datagram(
    socket socket.Socket
)

pub bind(endpoint address.Endpoint) !$Datagram:
    value := try socket.open(endpoint.address.family, socket.TYPE_DATAGRAM)
    onerror value.close()
    try value.bind(endpoint)
    ret Datagram(socket=move value)
..

pub open(family u8) !$Datagram:
    value := try socket.open(family, socket.TYPE_DATAGRAM)
    ret Datagram(socket=move value)
..

Datagram.connect(endpoint address.Endpoint) !void:
    try this.socket.connect(endpoint)
..

Datagram.recvFrom(buffer u8[], count u64) !socket.Received:
    ret try this.socket.recvFrom(buffer, count)
..

Datagram.sendTo(bytes str, endpoint address.Endpoint) !u64:
    ret try this.socket.sendTo(bytes, endpoint)
..

Datagram.localEndpoint() !address.Endpoint:
    ret try this.socket.localEndpoint()
..

Datagram.setNonBlocking(enabled bool) !void:
    try this.socket.setNonBlocking(enabled)
..

destr Datagram.close() !void:
    try this.socket.close()
..
