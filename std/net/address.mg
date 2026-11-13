mod net_address
# Allocation-free Internet address and endpoint values.

use "std:errors" as errors
use "std:strings" as strings
use "std:cast" as cast

pub const FAMILY_UNSPECIFIED u8 = 0
pub const FAMILY_IPV4 u8 = 4
pub const FAMILY_IPV6 u8 = 6

# Address words are stored in network byte order. IPv4 uses only word0.
pub IpAddress(
    family u8
    word0 u32
    word1 u32
    word2 u32
    word3 u32
)

pub Endpoint(
    address IpAddress
    port u16
)

pub unspecified() IpAddress:
    ret IpAddress(family=FAMILY_UNSPECIFIED, word0=0, word1=0, word2=0, word3=0)
..

pub ipv4(a u8, b u8, c u8, d u8) IpAddress:
    word u32 = (cast.u64to32(a) << 24) | (cast.u64to32(b) << 16) | (cast.u64to32(c) << 8) | cast.u64to32(d)
    ret IpAddress(family=FAMILY_IPV4, word0=word, word1=0, word2=0, word3=0)
..

pub ipv6(word0 u32, word1 u32, word2 u32, word3 u32) IpAddress:
    ret IpAddress(family=FAMILY_IPV6, word0=word0, word1=word1, word2=word2, word3=word3)
..

pub anyIpv4(port u16) Endpoint:
    ret Endpoint(address=ipv4(0, 0, 0, 0), port=port)
..

pub loopbackIpv4(port u16) Endpoint:
    ret Endpoint(address=ipv4(127, 0, 0, 1), port=port)
..

pub anyIpv6(port u16) Endpoint:
    ret Endpoint(address=ipv6(0, 0, 0, 0), port=port)
..

pub loopbackIpv6(port u16) Endpoint:
    ret Endpoint(address=ipv6(0, 0, 0, 1), port=port)
..

parseOctet(text str, start u64, finish u64) !u8:
    if finish <= start || finish - start > 3:
        throw errors.invalidArgument("invalid IPv4 address")
    ..
    value u64 = 0
    for i u64 = start to finish:
        ch u8 = strings.byteAt(text, i)
        if ch < 48 || ch > 57:
            throw errors.invalidArgument("invalid IPv4 address")
        ..
        value = value * 10 + cast.itou(ch - 48)
        if value > 255:
            throw errors.invalidArgument("invalid IPv4 address")
        ..
    ..
    ret cast.u64to8(value)
..

# Parses dotted-decimal IPv4 without allocating.
pub parseIpv4(text str) !IpAddress:
    length u64 = text.countBytes()
    octets := [4]u8
    part u64 = 0
    start u64 = 0
    i u64 = 0
    loop i <= length:
        boundary bool = i == length
        if boundary == false:
            boundary = strings.byteAt(text, i) == 46
        ..
        if boundary:
            if part >= 4:
                throw errors.invalidArgument("invalid IPv4 address")
            ..
            octets[part] = try parseOctet(text, start, i)
            part = part + 1
            start = i + 1
        ..
        i = i + 1
    ..
    if part != 4:
        throw errors.invalidArgument("invalid IPv4 address")
    ..
    ret ipv4(octets[0], octets[1], octets[2], octets[3])
..

hexValue(ch u8) !u16:
    if ch >= 48 && ch <= 57:
        ret cast.u64to16(ch - 48)
    elif ch >= 65 && ch <= 70:
        ret cast.u64to16(ch - 65 + 10)
    elif ch >= 97 && ch <= 102:
        ret cast.u64to16(ch - 97 + 10)
    ..
    throw errors.invalidArgument("invalid IPv6 address")
..

# Parses hexadecimal IPv6, including one compressed :: run.
pub parseIpv6(text str) !IpAddress:
    length := text.countBytes()
    if length < 2:
        throw errors.invalidArgument("invalid IPv6 address")
    ..
    groups := [8]u16
    count u64 = 0
    compression i64 = -1
    index u64 = 0
    if strings.byteAt(text, 0) == 58:
        if strings.byteAt(text, 1) != 58:
            throw errors.invalidArgument("invalid IPv6 address")
        ..
        compression = 0
        index = 2
    ..
    loop index < length:
        if count >= 8:
            throw errors.invalidArgument("invalid IPv6 address")
        ..
        value u16 = 0
        digits u64 = 0
        loop index < length && strings.byteAt(text, index) != 58:
            if digits == 4:
                throw errors.invalidArgument("invalid IPv6 address")
            ..
            value = (value << 4) | try hexValue(strings.byteAt(text, index))
            digits = digits + 1
            index = index + 1
        ..
        if digits == 0:
            throw errors.invalidArgument("invalid IPv6 address")
        ..
        groups[count] = value
        count = count + 1
        if index < length:
            index = index + 1
            if index < length && strings.byteAt(text, index) == 58:
                if compression >= 0:
                    throw errors.invalidArgument("invalid IPv6 address")
                ..
                compression = cast.utoi(count)
                index = index + 1
                if index == length:
                    break
                ..
            ..
        ..
    ..
    if compression < 0:
        if count != 8:
            throw errors.invalidArgument("invalid IPv6 address")
        ..
    else:
        if count >= 8:
            throw errors.invalidArgument("invalid IPv6 compression")
        ..
        compressedIndex u64 = cast.itou(compression)
        tail u64 = count - compressedIndex
        for moved u64 = 0 to tail:
            bounded 7 - moved < groups.count(), count - 1 - moved < groups.count():
                groups[7 - moved] = groups[count - 1 - moved]
            ..
        ..
        for zeroIndex u64 = compressedIndex to 8 - tail:
            bounded zeroIndex < groups.count():
                groups[zeroIndex] = 0
            ..
        ..
    ..
    word0 u32 = (cast.u64to32(groups[0]) << 16) | cast.u64to32(groups[1])
    word1 u32 = (cast.u64to32(groups[2]) << 16) | cast.u64to32(groups[3])
    word2 u32 = (cast.u64to32(groups[4]) << 16) | cast.u64to32(groups[5])
    word3 u32 = (cast.u64to32(groups[6]) << 16) | cast.u64to32(groups[7])
    ret ipv6(word0, word1, word2, word3)
..

pub parse(text str) !IpAddress:
    for i u64 = 0 to text.countBytes():
        if strings.byteAt(text, i) == 58:
            ret try parseIpv6(text)
        ..
    ..
    ret try parseIpv4(text)
..

pub IpAddress.isIpv4() bool:
    ret this.family == FAMILY_IPV4
..

pub IpAddress.isIpv6() bool:
    ret this.family == FAMILY_IPV6
..

pub IpAddress.equal(other IpAddress) bool:
    ret this.family == other.family && this.word0 == other.word0 && this.word1 == other.word1 && this.word2 == other.word2 && this.word3 == other.word3
..

pub Endpoint.equal(other Endpoint) bool:
    ret this.port == other.port && this.address.equal(other.address)
..
