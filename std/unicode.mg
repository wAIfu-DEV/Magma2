mod unicode
# Allocation-free Unicode scalar and UTF-16 surrogate helpers.

use "std:cast" as cast
use "std:errors" as errors

pub const REPLACEMENT u32 = 0xFFFD
pub const MAX_SCALAR u32 = 0x10FFFF

# A UTF-16 surrogate pair representing one supplementary scalar.
pub SurrogatePair(high u16, low u16)

# Reports whether cp is a Unicode scalar value.
# @complexity O(1)
pub isScalar(cp u32) bool:
    ret cp <= MAX_SCALAR && (cp < 0xD800 || cp > 0xDFFF)
..

# Reports whether unit starts a UTF-16 surrogate pair.
# @complexity O(1)
pub isHighSurrogate(unit u16) bool:
    ret unit >= 0xD800 && unit <= 0xDBFF
..

# Reports whether unit completes a UTF-16 surrogate pair.
# @complexity O(1)
pub isLowSurrogate(unit u16) bool:
    ret unit >= 0xDC00 && unit <= 0xDFFF
..

# Combines a validated UTF-16 surrogate pair into one scalar value.
# @throws invalidArgument when the units do not form a pair
# @complexity O(1)
pub combineSurrogates(high u16, low u16) !u32:
    if isHighSurrogate(high) == false || isLowSurrogate(low) == false:
        throw errors.invalidArgument("invalid UTF-16 surrogate pair")
    ..
    highValue u32 = cast.u64to32(cast.u16to64(high - 0xD800))
    lowValue u32 = cast.u64to32(cast.u16to64(low - 0xDC00))
    ret ((highValue << 10) | lowValue) + 0x10000
..

# Splits a supplementary scalar into its UTF-16 surrogate pair.
# @throws invalidArgument when cp does not require a surrogate pair
# @complexity O(1)
pub splitSurrogate(cp u32) !SurrogatePair:
    if isScalar(cp) == false || cp < 0x10000:
        throw errors.invalidArgument("scalar does not require a UTF-16 surrogate pair")
    ..
    value u32 = cp - 0x10000
    high u16 = cast.u64to16(cast.u32to64((value >> 10) + 0xD800))
    low u16 = cast.u64to16(cast.u32to64((value & 0x3FF) + 0xDC00))
    ret SurrogatePair(high=high, low=low)
..
