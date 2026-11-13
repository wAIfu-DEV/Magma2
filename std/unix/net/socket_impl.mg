mod net_socket_impl_unix
# POSIX socket backend. Native address layouts remain private to this module.

use "std:c" as c
use "std:cast" as cast
use "std:errors" as errors
use "std:slices" as slices
use "std:strings" as strings
use "std:net/address" as address
use "std:net/byte_order" as byte_order

SockAddrIn(
    family u16
    port u16
    addr u32
    zero u64
)

SockAddrIn6(
    family u16
    port u16
    flowInfo u32
    addr0 u32
    addr1 u32
    addr2 u32
    addr3 u32
    scopeId u32
)

SockAddrStorage(
    part0 u128
    part1 u128
    part2 u128
    part3 u128
    part4 u128
    part5 u128
    part6 u128
    part7 u128
)

NativeAddress(
    pointer ptr
    length u32
)

ext ext_socket socket(domain c.int, kind c.int, protocol c.int) c.int
ext ext_bind bind(fd c.int, addr ptr, length c.unsigned_int) c.int
ext ext_listen listen(fd c.int, backlog c.int) c.int
ext ext_accept accept(fd c.int, addr ptr, length c.unsigned_int*) c.int
@platform("linux", "android")
ext ext_accept4 accept4(fd c.int, addr ptr, length c.unsigned_int*, flags c.int) c.int
ext ext_connect connect(fd c.int, addr ptr, length c.unsigned_int) c.int
ext ext_close close(fd c.int) c.int
ext ext_recv recv(fd c.int, buffer ptr, length u64, flags c.int) i64
ext ext_send send(fd c.int, buffer ptr, length u64, flags c.int) i64
ext ext_recvfrom recvfrom(fd c.int, buffer ptr, length u64, flags c.int, addr ptr, addrLength c.unsigned_int*) i64
ext ext_sendto sendto(fd c.int, buffer ptr, length u64, flags c.int, addr ptr, addrLength c.unsigned_int) i64
ext ext_shutdown shutdown(fd c.int, how c.int) c.int
ext ext_fcntl fcntl(fd c.int, command c.int, value c.int) c.int
ext ext_setsockopt setsockopt(fd c.int, level c.int, name c.int, value ptr, length c.unsigned_int) c.int
ext ext_getsockname getsockname(fd c.int, addr ptr, length c.unsigned_int*) c.int
ext ext_getpeername getpeername(fd c.int, addr ptr, length c.unsigned_int*) c.int

@platform("linux", "android")
ext ext_errno_location __errno_location() i32*

@platform("darwin", "ios", "freebsd", "netbsd", "openbsd")
ext ext_errno_location __error() i32*

lastFailure(message str) error:
    code i32 = 0
    # SAFETY: errno_location returns the platform thread-local errno pointer.
    unsafe:
        code = *ext_errno_location()
    ..
    if code == 11 || code == 35:
        ret errors.wouldBlock(message)
    elif code == 110 || code == 60:
        ret errors.timedOut(message)
    elif code == 104 || code == 54:
        ret errors.connectionReset(message)
    elif code == 111 || code == 61:
        ret errors.connectionRefused(message)
    elif code == 98 || code == 48:
        ret errors.addressInUse(message)
    ..
    ret errors.native(cast.u64to32(cast.itou(cast.i32to64(code))), message)
..

fdToPtr(fd i32) ptr:
    ret cast.utop(cast.itou(cast.i32to64(fd)))
..

ptrToFd(handle ptr) i32:
    ret cast.i64to32(cast.utoi(cast.ptou(handle)))
..

@platform("linux", "android")
nativeIpv6Family() i32:
    ret 10
..

@platform("darwin", "ios")
nativeIpv6Family() i32:
    ret 30
..

@platform("freebsd")
nativeIpv6Family() i32:
    ret 28
..

@platform("netbsd", "openbsd")
nativeIpv6Family() i32:
    ret 24
..

@platform("linux", "android")
nativeNonBlockingFlag() i32:
    ret 2048
..

@platform("darwin", "ios", "freebsd", "netbsd", "openbsd")
nativeNonBlockingFlag() i32:
    ret 4
..

nativeFamily(family u8) !i32:
    if family == address.FAMILY_IPV4:
        ret 2
    elif family == address.FAMILY_IPV6:
        ret nativeIpv6Family()
    ..
    throw errors.invalidArgument("unsupported address family")
..

fillAddress(endpoint address.Endpoint, storage SockAddrStorage*) !NativeAddress:
    family i32 = try nativeFamily(endpoint.address.family)
    if endpoint.address.family == address.FAMILY_IPV4:
        native SockAddrIn*
        unsafe: native = storage ..
        native.family = cast.u64to16(cast.itou(family))
        byte_order.store16(addrof native.port, endpoint.port)
        byte_order.store32(addrof native.addr, endpoint.address.word0)
        native.zero = 0
        ret NativeAddress(pointer=native, length=cast.u64to32(sizeof SockAddrIn))
    ..
    native6 SockAddrIn6*
    unsafe: native6 = storage ..
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
    native SockAddrIn*
    unsafe: native = storage ..
    if native.family == 2:
        word u32 = byte_order.load32(addrof native.addr)
        ip := address.ipv4(cast.u64to8((word >> 24) & 255), cast.u64to8((word >> 16) & 255), cast.u64to8((word >> 8) & 255), cast.u64to8(word & 255))
        ret address.Endpoint(address=ip, port=byte_order.load16(addrof native.port))
    ..
    native6 SockAddrIn6*
    unsafe: native6 = storage ..
    ip6 := address.ipv6(byte_order.load32(addrof native6.addr0), byte_order.load32(addrof native6.addr1), byte_order.load32(addrof native6.addr2), byte_order.load32(addrof native6.addr3))
    ret address.Endpoint(address=ip6, port=byte_order.load16(addrof native6.port))
..

pub openBlocking(family u8, kind u8) !ptr:
    domain := try nativeFamily(family)
    nativeKind i32 = 1
    if kind == 2:
        nativeKind = 2
    ..
    fd i32 = ext_socket(domain, nativeKind, 0)
    if fd < 0:
        throw lastFailure("socket creation failed")
    ..
    ret fdToPtr(fd)
..

@platform("linux", "android")
pub openNonBlocking(family u8, kind u8) !ptr:
    domain := try nativeFamily(family)
    nativeKind i32 = 1 | 2048 | 0x80000
    if kind == 2:
        nativeKind = 2 | 2048 | 0x80000
    ..
    fd i32 = ext_socket(domain, nativeKind, 0)
    if fd < 0: throw lastFailure("socket creation failed") ..
    ret fdToPtr(fd)
..

@platform("darwin", "ios", "freebsd", "netbsd", "openbsd")
pub openNonBlocking(family u8, kind u8) !ptr:
    handle := try openBlocking(family, kind)
    onerror close(handle)
    try setNonBlocking(handle, true)
    ret handle
..

pub bind(handle ptr, endpoint address.Endpoint) !void:
    storage SockAddrStorage
    native := try fillAddress(endpoint, addrof storage)
    if ext_bind(ptrToFd(handle), native.pointer, native.length) != 0:
        throw lastFailure("socket bind failed")
    ..
..

pub listen(handle ptr, backlog u32) !void:
    if ext_listen(ptrToFd(handle), cast.u32toi32(cast.u64to32(backlog))) != 0:
        throw lastFailure("socket listen failed")
    ..
..

pub acceptBlocking(handle ptr) !ptr:
    storage SockAddrStorage
    length u32 = cast.u64to32(sizeof SockAddrStorage)
    fd i32 = ext_accept(ptrToFd(handle), addrof storage, addrof length)
    if fd < 0:
        throw lastFailure("socket accept failed")
    ..
    ret fdToPtr(fd)
..

@platform("linux", "android")
pub acceptNonBlocking(handle ptr) !ptr:
    storage SockAddrStorage
    length u32 = cast.u64to32(sizeof SockAddrStorage)
    fd i32 = ext_accept4(ptrToFd(handle), addrof storage, addrof length, 2048 | 0x80000)
    if fd < 0: throw lastFailure("socket accept failed") ..
    ret fdToPtr(fd)
..

@platform("darwin", "ios", "freebsd", "netbsd", "openbsd")
pub acceptNonBlocking(handle ptr) !ptr:
    accepted := try acceptBlocking(handle)
    onerror close(accepted)
    try setNonBlocking(accepted, true)
    ret accepted
..

pub connect(handle ptr, endpoint address.Endpoint) !void:
    storage SockAddrStorage
    native := try fillAddress(endpoint, addrof storage)
    if ext_connect(ptrToFd(handle), native.pointer, native.length) != 0:
        throw lastFailure("socket connect failed")
    ..
..

pub setNonBlocking(handle ptr, enabled bool) !void:
    F_GETFL i32 = 3
    F_SETFL i32 = 4
    O_NONBLOCK i32 = nativeNonBlockingFlag()
    fd := ptrToFd(handle)
    flags i32 = ext_fcntl(fd, F_GETFL, 0)
    if flags < 0:
        throw lastFailure("socket flag query failed")
    ..
    if enabled:
        flags = flags | O_NONBLOCK
    else:
        flags = flags & (0 - O_NONBLOCK - 1)
    ..
    if ext_fcntl(fd, F_SETFL, flags) != 0:
        throw lastFailure("socket flag update failed")
    ..
..

pub setReuseAddress(handle ptr, enabled bool) !void:
    value i32 = 0
    if enabled:
        value = 1
    ..
    if ext_setsockopt(ptrToFd(handle), 1, 2, addrof value, cast.u64to32(sizeof i32)) != 0:
        throw lastFailure("socket option update failed")
    ..
..

pub localEndpoint(handle ptr) !address.Endpoint:
    storage SockAddrStorage
    length u32 = cast.u64to32(sizeof SockAddrStorage)
    if ext_getsockname(ptrToFd(handle), addrof storage, addrof length) != 0:
        throw lastFailure("socket local address query failed")
    ..
    ret try readAddress(addrof storage)
..

pub peerEndpoint(handle ptr) !address.Endpoint:
    storage SockAddrStorage
    length u32 = cast.u64to32(sizeof SockAddrStorage)
    if ext_getpeername(ptrToFd(handle), addrof storage, addrof length) != 0:
        throw lastFailure("socket peer address query failed")
    ..
    ret try readAddress(addrof storage)
..

pub recv(handle ptr, buffer u8[], count u64) !u64:
    if count > slices.count(buffer):
        throw errors.invalidArgument("socket receive would overflow")
    ..
    result i64 = ext_recv(ptrToFd(handle), slices.toPtr(buffer), count, 0)
    if result < 0:
        throw lastFailure("socket receive failed")
    ..
    ret cast.itou(result)
..

pub send(handle ptr, bytes str) !u64:
    result i64 = ext_send(ptrToFd(handle), strings.toPtr(bytes), bytes.countBytes(), 0)
    if result < 0:
        throw lastFailure("socket send failed")
    ..
    ret cast.itou(result)
..

pub recvFrom(handle ptr, buffer u8[], count u64, source address.Endpoint*) !u64:
    if count > slices.count(buffer):
        throw errors.invalidArgument("socket receive would overflow")
    ..
    storage SockAddrStorage
    length u32 = cast.u64to32(sizeof SockAddrStorage)
    result i64 = ext_recvfrom(ptrToFd(handle), slices.toPtr(buffer), count, 0, addrof storage, addrof length)
    if result < 0:
        throw lastFailure("datagram receive failed")
    ..
    *source = try readAddress(addrof storage)
    ret cast.itou(result)
..

pub sendTo(handle ptr, bytes str, endpoint address.Endpoint) !u64:
    storage SockAddrStorage
    native := try fillAddress(endpoint, addrof storage)
    result i64 = ext_sendto(ptrToFd(handle), strings.toPtr(bytes), bytes.countBytes(), 0, native.pointer, native.length)
    if result < 0:
        throw lastFailure("datagram send failed")
    ..
    ret cast.itou(result)
..

pub shutdown(handle ptr, direction u8) !void:
    how i32 = 2
    if direction == 1:
        how = 0
    elif direction == 2:
        how = 1
    ..
    if ext_shutdown(ptrToFd(handle), how) != 0:
        throw lastFailure("socket shutdown failed")
    ..
..

pub close(handle ptr) !void:
    if ext_close(ptrToFd(handle)) != 0:
        throw lastFailure("socket close failed")
    ..
..
