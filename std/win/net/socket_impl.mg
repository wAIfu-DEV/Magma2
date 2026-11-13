mod net_socket_impl_win
# Winsock backend with one Winsock reference owned by every returned socket.

link "ws2_32"

use "std:c" as c
use "std:cast" as cast
use "std:errors" as errors
use "std:slices" as slices
use "std:strings" as strings
use "std:net/address" as address
use "std:net/byte_order" as byte_order
use "std:win/net/runtime" as runtime

SockAddrIn(family u16, port u16, addr u32, zero u64)
SockAddrIn6(family u16, port u16, flowInfo u32, addr0 u32, addr1 u32, addr2 u32, addr3 u32, scopeId u32)
SockAddrStorage(part0 u128, part1 u128, part2 u128, part3 u128, part4 u128, part5 u128, part6 u128, part7 u128)
WsaData(part0 u128, part1 u128, part2 u128, part3 u128, part4 u128, part5 u128, part6 u128, part7 u128, part8 u128, part9 u128, part10 u128, part11 u128, part12 u128, part13 u128, part14 u128, part15 u128, part16 u128, part17 u128, part18 u128, part19 u128, part20 u128, part21 u128, part22 u128, part23 u128, part24 u128, part25 u128, part26 u128, part27 u128, part28 u128, part29 u128, part30 u128, part31 u128)
NativeAddress(pointer ptr, length i32)

ext ext_WSAStartup WSAStartup(version u16, data ptr) i32
ext ext_WSACleanup WSACleanup() i32
ext ext_WSAGetLastError WSAGetLastError() i32
ext ext_socket socket(domain i32, kind i32, protocol i32) u64
ext ext_bind bind(socket u64, addr ptr, length i32) i32
ext ext_listen listen(socket u64, backlog i32) i32
ext ext_accept accept(socket u64, addr ptr, length i32*) u64
ext ext_connect connect(socket u64, addr ptr, length i32) i32
ext ext_closesocket closesocket(socket u64) i32
ext ext_recv recv(socket u64, buffer ptr, length i32, flags i32) i32
ext ext_send send(socket u64, buffer ptr, length i32, flags i32) i32
ext ext_recvfrom recvfrom(socket u64, buffer ptr, length i32, flags i32, addr ptr, addrLength i32*) i32
ext ext_sendto sendto(socket u64, buffer ptr, length i32, flags i32, addr ptr, addrLength i32) i32
ext ext_shutdown shutdown(socket u64, how i32) i32
ext ext_ioctlsocket ioctlsocket(socket u64, command c.long, value c.unsigned_long*) i32
ext ext_setsockopt setsockopt(socket u64, level i32, name i32, value ptr, length i32) i32
ext ext_getsockname getsockname(socket u64, addr ptr, length i32*) i32
ext ext_getpeername getpeername(socket u64, addr ptr, length i32*) i32

socketValue(handle ptr) u64:
    ret cast.ptou(handle)
..

socketPointer(value u64) ptr:
    ret cast.utop(value)
..

nativeFailure(message str) error:
    code i32 = ext_WSAGetLastError()
    if code == 10035:
        ret errors.wouldBlock(message)
    elif code == 10060:
        ret errors.timedOut(message)
    elif code == 10054:
        ret errors.connectionReset(message)
    elif code == 10061:
        ret errors.connectionRefused(message)
    elif code == 10048:
        ret errors.addressInUse(message)
    ..
    ret errors.native(cast.u64to32(cast.itou(cast.i32to64(code))), message)
..

nativeFamily(family u8) !i32:
    if family == address.FAMILY_IPV4:
        ret 2
    elif family == address.FAMILY_IPV6:
        ret 23
    ..
    throw errors.invalidArgument("unsupported address family")
..

fillAddress(endpoint address.Endpoint, storage SockAddrStorage*) !NativeAddress:
    family := try nativeFamily(endpoint.address.family)
    if endpoint.address.family == address.FAMILY_IPV4:
        native SockAddrIn* = storage
        native.family = cast.u64to16(cast.itou(family))
        byte_order.store16(addrof native.port, endpoint.port)
        byte_order.store32(addrof native.addr, endpoint.address.word0)
        native.zero = 0
        ret NativeAddress(pointer=native, length=cast.u64to32(sizeof SockAddrIn))
    ..
    native6 SockAddrIn6* = storage
    native6.family = cast.u64to16(cast.itou(family))
    byte_order.store16(addrof native6.port, endpoint.port)
    native6.flowInfo = 0
    byte_order.store32(addrof native6.addr0, endpoint.address.word0)
    byte_order.store32(addrof native6.addr1, endpoint.address.word1)
    byte_order.store32(addrof native6.addr2, endpoint.address.word2)
    byte_order.store32(addrof native6.addr3, endpoint.address.word3)
    native6.scopeId = 0
    ret NativeAddress(pointer=native6, length=cast.u64to32(sizeof SockAddrIn6))
..

readAddress(storage SockAddrStorage*) !address.Endpoint:
    native SockAddrIn* = storage
    if native.family == 2:
        word u32 = byte_order.load32(addrof native.addr)
        ip := address.ipv4(cast.u64to8((word >> 24) & 255), cast.u64to8((word >> 16) & 255), cast.u64to8((word >> 8) & 255), cast.u64to8(word & 255))
        ret address.Endpoint(address=ip, port=byte_order.load16(addrof native.port))
    ..
    native6 SockAddrIn6* = storage
    ip6 := address.ipv6(byte_order.load32(addrof native6.addr0), byte_order.load32(addrof native6.addr1), byte_order.load32(addrof native6.addr2), byte_order.load32(addrof native6.addr3))
    ret address.Endpoint(address=ip6, port=byte_order.load16(addrof native6.port))
..

checkedLength(length u64) !i32:
    if length > 0x7FFFFFFF:
        throw errors.invalidArgument("socket buffer exceeds native limit")
    ..
    ret cast.u64to32(length)
..

pub openBlocking(family u8, kind u8) !ptr:
    try runtime.ensure()
    domain := try nativeFamily(family)
    nativeKind i32 = 1
    protocol i32 = 6
    if kind == 2:
        nativeKind = 2
        protocol = 17
    ..
    value u64 = ext_socket(domain, nativeKind, protocol)
    if value == 0 - 1:
        throw nativeFailure("socket creation failed")
    ..
    ret socketPointer(value)
..

pub openNonBlocking(family u8, kind u8) !ptr:
    handle := try openBlocking(family, kind)
    onerror close(handle)
    try setNonBlocking(handle, true)
    ret handle
..

pub bind(handle ptr, endpoint address.Endpoint) !void:
    storage SockAddrStorage
    native := try fillAddress(endpoint, addrof storage)
    if ext_bind(socketValue(handle), native.pointer, native.length) != 0:
        throw nativeFailure("socket bind failed")
    ..
..

pub listen(handle ptr, backlog u32) !void:
    if ext_listen(socketValue(handle), cast.u64to32(backlog)) != 0:
        throw nativeFailure("socket listen failed")
    ..
..

pub acceptBlocking(handle ptr) !ptr:
    try runtime.ensure()
    storage SockAddrStorage
    length i32 = cast.u64to32(sizeof SockAddrStorage)
    value u64 = ext_accept(socketValue(handle), addrof storage, addrof length)
    if value == 0 - 1:
        throw nativeFailure("socket accept failed")
    ..
    ret socketPointer(value)
..

pub acceptNonBlocking(handle ptr) !ptr:
    accepted := try acceptBlocking(handle)
    onerror close(accepted)
    try setNonBlocking(accepted, true)
    ret accepted
..

pub connect(handle ptr, endpoint address.Endpoint) !void:
    storage SockAddrStorage
    native := try fillAddress(endpoint, addrof storage)
    if ext_connect(socketValue(handle), native.pointer, native.length) != 0:
        throw nativeFailure("socket connect failed")
    ..
..

pub setNonBlocking(handle ptr, enabled bool) !void:
    value u32 = 0
    if enabled:
        value = 1
    ..
    if ext_ioctlsocket(socketValue(handle), 0x8004667E, addrof value) != 0:
        throw nativeFailure("socket flag update failed")
    ..
..

pub setReuseAddress(handle ptr, enabled bool) !void:
    value i32 = 0
    if enabled:
        value = 1
    ..
    if ext_setsockopt(socketValue(handle), 0xFFFF, 4, addrof value, cast.u64to32(sizeof i32)) != 0:
        throw nativeFailure("socket option update failed")
    ..
..

pub localEndpoint(handle ptr) !address.Endpoint:
    storage SockAddrStorage
    length i32 = cast.u64to32(sizeof SockAddrStorage)
    if ext_getsockname(socketValue(handle), addrof storage, addrof length) != 0:
        throw nativeFailure("socket local address query failed")
    ..
    ret try readAddress(addrof storage)
..

pub peerEndpoint(handle ptr) !address.Endpoint:
    storage SockAddrStorage
    length i32 = cast.u64to32(sizeof SockAddrStorage)
    if ext_getpeername(socketValue(handle), addrof storage, addrof length) != 0:
        throw nativeFailure("socket peer address query failed")
    ..
    ret try readAddress(addrof storage)
..

pub recv(handle ptr, buffer u8[], count u64) !u64:
    if count > slices.count(buffer):
        throw errors.invalidArgument("socket receive would overflow")
    ..
    result i32 = ext_recv(socketValue(handle), slices.toPtr(buffer), try checkedLength(count), 0)
    if result < 0:
        throw nativeFailure("socket receive failed")
    ..
    ret cast.itou(cast.i32to64(result))
..

pub send(handle ptr, bytes str) !u64:
    result i32 = ext_send(socketValue(handle), strings.toPtr(bytes), try checkedLength(bytes.countBytes()), 0)
    if result < 0:
        throw nativeFailure("socket send failed")
    ..
    ret cast.itou(cast.i32to64(result))
..

pub recvFrom(handle ptr, buffer u8[], count u64, source address.Endpoint*) !u64:
    if count > slices.count(buffer):
        throw errors.invalidArgument("socket receive would overflow")
    ..
    storage SockAddrStorage
    length i32 = cast.u64to32(sizeof SockAddrStorage)
    result i32 = ext_recvfrom(socketValue(handle), slices.toPtr(buffer), try checkedLength(count), 0, addrof storage, addrof length)
    if result < 0:
        throw nativeFailure("datagram receive failed")
    ..
    *source = try readAddress(addrof storage)
    ret cast.itou(cast.i32to64(result))
..

pub sendTo(handle ptr, bytes str, endpoint address.Endpoint) !u64:
    storage SockAddrStorage
    native := try fillAddress(endpoint, addrof storage)
    result i32 = ext_sendto(socketValue(handle), strings.toPtr(bytes), try checkedLength(bytes.countBytes()), 0, native.pointer, native.length)
    if result < 0:
        throw nativeFailure("datagram send failed")
    ..
    ret cast.itou(cast.i32to64(result))
..

pub shutdown(handle ptr, direction u8) !void:
    how i32 = 2
    if direction == 1:
        how = 0
    elif direction == 2:
        how = 1
    ..
    if ext_shutdown(socketValue(handle), how) != 0:
        throw nativeFailure("socket shutdown failed")
    ..
..

pub close(handle ptr) !void:
    closeCode i32 = ext_closesocket(socketValue(handle))
    if closeCode != 0:
        throw nativeFailure("socket close failed")
    ..
..
