mod net_byte_order
# Pure helpers for reading and writing integer fields in network byte order.

use "std:cast" as cast

# Writes a u16 to native storage in big-endian (network) byte order.
pub store16(target u16* bounded 1, value u16) void:
    bytes u8* = cast.reinterpret[u8](target)
    bounded bytes by 2:
        bytes[0] = cast.u64to8(value >> 8)
        bytes[1] = cast.u64to8(value & 0xFF)
    ..
..

# Reads a big-endian (network-order) u16 from native storage.
pub load16(source u16* bounded 1) u16:
    bytes u8* = cast.reinterpret[u8](source)
    bounded bytes by 2:
        ret (cast.u64to16(bytes[0]) << 8) | cast.u64to16(bytes[1])
    ..
..

# Writes a u32 to native storage in big-endian (network) byte order.
pub store32(target u32* bounded 1, value u32) void:
    bytes u8* = cast.reinterpret[u8](target)
    bounded bytes by 4:
        bytes[0] = cast.u64to8(value >> 24)
        bytes[1] = cast.u64to8((value >> 16) & 0xFF)
        bytes[2] = cast.u64to8((value >> 8) & 0xFF)
        bytes[3] = cast.u64to8(value & 0xFF)
    ..
..

# Reads a big-endian (network-order) u32 from native storage.
pub load32(source u32* bounded 1) u32:
    bytes u8* = cast.reinterpret[u8](source)
    bounded bytes by 4:
        ret (cast.u64to32(bytes[0]) << 24) | (cast.u64to32(bytes[1]) << 16) | (cast.u64to32(bytes[2]) << 8) | cast.u64to32(bytes[3])
    ..
..
