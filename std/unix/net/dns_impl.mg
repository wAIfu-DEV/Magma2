mod net_dns_impl_unix

use "std:c" as c
use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:strings" as strings
use "std:net/address" as address
use "std:net/byte_order" as byte_order

SockAddrIn(family u16, port u16, addr u32, zero u64)
SockAddrIn6(family u16, port u16, flowInfo u32, addr0 u32, addr1 u32, addr2 u32, addr3 u32, scopeId u32)
AddrInfo(flags i32, family i32, kind i32, protocol i32, addrLength u32, addr ptr, canonicalName u8*, next AddrInfo*)

pub Resolved(endpoints address.Endpoint*, count u64)

ext ext_getaddrinfo getaddrinfo(node u8*, service u8*, hints AddrInfo*, result AddrInfo**) i32
ext ext_freeaddrinfo freeaddrinfo(result AddrInfo*) void

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

decode(native ptr) !address.Endpoint:
    # SAFETY: getaddrinfo supplies sockaddr storage and its family field selects
    # the corresponding IPv4 or IPv6 native layout.
    unsafe:
    ipv4 SockAddrIn* = native
    if ipv4.family == 2:
        word u32 = byte_order.load32(addrof ipv4.addr)
        ip := address.ipv4(cast.u64to8((word >> 24) & 255), cast.u64to8((word >> 16) & 255), cast.u64to8((word >> 8) & 255), cast.u64to8(word & 255))
        ret address.Endpoint(address=ip, port=byte_order.load16(addrof ipv4.port))
    ..
    ipv6 SockAddrIn6* = native
    if ipv6.family != nativeIpv6Family():
        throw errors.failure("DNS returned an unsupported address family")
    ..
    ip6 := address.ipv6(byte_order.load32(addrof ipv6.addr0), byte_order.load32(addrof ipv6.addr1), byte_order.load32(addrof ipv6.addr2), byte_order.load32(addrof ipv6.addr3))
      ret address.Endpoint(address=ip6, port=byte_order.load16(addrof ipv6.port))
    ..
..

pub resolve(host str, service str, family u8, maxResults u64) !Resolved:
    a := ctx.alloc
    # SAFETY: getaddrinfo owns cursor nodes until freeaddrinfo; endpoints has
    # count slots and index is checked before every write.
    unsafe:
    hints AddrInfo
    hints.flags = 0
    hints.family = 0
    if family == address.FAMILY_IPV4:
        hints.family = 2
    elif family == address.FAMILY_IPV6:
        hints.family = nativeIpv6Family()
    ..
    hints.kind = 0
    hints.protocol = 0
    hints.addrLength = 0
    hints.addr = none
    hints.canonicalName = none
    hints.next = none
    result AddrInfo* = none
    code i32 = ext_getaddrinfo(strings.toCstrNoCopy(host), strings.toCstrNoCopy(service), addrof hints, addrof result)
    if code != 0:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(code))), "DNS lookup failed")
    ..
    defer ext_freeaddrinfo(result)
    count u64 = 0
    cursor AddrInfo* = result
    loop cursor != none && count < maxResults:
        if cursor.addr != none:
            count = count + 1
        ..
        cursor = cursor.next
    ..
    if count == 0:
        throw errors.notFound("DNS returned no addresses")
    ..
    endpoints address.Endpoint* = try a.allocT[address.Endpoint](count)
    onerror a.free(endpoints)
    cursor = result
    index u64 = 0
    loop cursor != none && index < count:
        if cursor.addr != none:
            endpoints[index] = try decode(cursor.addr)
            index = index + 1
        ..
        cursor = cursor.next
    ..
      ret Resolved(endpoints=endpoints, count=count)
    ..
..
