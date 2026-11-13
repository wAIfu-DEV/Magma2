mod net_dns_impl_win

link "ws2_32"

use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:strings" as strings
use "std:net/address" as address
use "std:net/byte_order" as byte_order
use "std:win/net/runtime" as runtime

SockAddrIn(family u16, port u16, addr u32, zero u64)
SockAddrIn6(family u16, port u16, flowInfo u32, addr0 u32, addr1 u32, addr2 u32, addr3 u32, scopeId u32)
AddrInfo(flags i32, family i32, kind i32, protocol i32, addrLength u64, canonicalName u8*, addr ptr, next AddrInfo*)
WsaData(part0 u128, part1 u128, part2 u128, part3 u128, part4 u128, part5 u128, part6 u128, part7 u128, part8 u128, part9 u128, part10 u128, part11 u128, part12 u128, part13 u128, part14 u128, part15 u128, part16 u128, part17 u128, part18 u128, part19 u128, part20 u128, part21 u128, part22 u128, part23 u128, part24 u128, part25 u128, part26 u128, part27 u128, part28 u128, part29 u128, part30 u128, part31 u128)

pub Resolved(endpoints address.Endpoint*, count u64)

ext ext_WSAStartup WSAStartup(version u16, data ptr) i32
ext ext_WSACleanup WSACleanup() i32
ext ext_getaddrinfo getaddrinfo(node u8*, service u8*, hints AddrInfo*, result AddrInfo**) i32
ext ext_freeaddrinfo freeaddrinfo(result AddrInfo*) void

decode(native ptr) !address.Endpoint:
    ipv4 SockAddrIn* = native
    if ipv4.family == 2:
        word u32 = byte_order.load32(addrof ipv4.addr)
        ip := address.ipv4(cast.u64to8((word >> 24) & 255), cast.u64to8((word >> 16) & 255), cast.u64to8((word >> 8) & 255), cast.u64to8(word & 255))
        ret address.Endpoint(address=ip, port=byte_order.load16(addrof ipv4.port))
    ..
    ipv6 SockAddrIn6* = native
    if ipv6.family != 23:
        throw errors.failure("DNS returned an unsupported address family")
    ..
    ip6 := address.ipv6(byte_order.load32(addrof ipv6.addr0), byte_order.load32(addrof ipv6.addr1), byte_order.load32(addrof ipv6.addr2), byte_order.load32(addrof ipv6.addr3))
    ret address.Endpoint(address=ip6, port=byte_order.load16(addrof ipv6.port))
..

pub resolve(host str, service str, family u8, maxResults u64) !Resolved:
    a := ctx.alloc
    try runtime.ensure()
    hints AddrInfo
    hints.flags = 0
    hints.family = 0
    if family == address.FAMILY_IPV4:
        hints.family = 2
    elif family == address.FAMILY_IPV6:
        hints.family = 23
    ..
    hints.kind = 0
    hints.protocol = 0
    hints.addrLength = 0
    hints.canonicalName = none
    hints.addr = none
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
