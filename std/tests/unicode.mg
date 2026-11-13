mod main

use "std:errors" as errors
use "std:unicode" as unicode

pub main() !void:
    if unicode.isScalar(0) == false || unicode.isScalar(0x10FFFF) == false:
        throw errors.failure("valid Unicode scalar rejected")
    ..
    if unicode.isScalar(0xD800) || unicode.isScalar(0xDFFF) || unicode.isScalar(0x110000):
        throw errors.failure("invalid Unicode scalar accepted")
    ..
    if unicode.isHighSurrogate(0xD83D) == false || unicode.isLowSurrogate(0xDE25) == false:
        throw errors.failure("UTF-16 surrogate classification changed")
    ..
    cp := try unicode.combineSurrogates(0xD83D, 0xDE25)
    if cp != 0x1F625:
        throw errors.failure("UTF-16 surrogate combination changed")
    ..
    pair := try unicode.splitSurrogate(cp)
    if pair.high != 0xD83D || pair.low != 0xDE25:
        throw errors.failure("UTF-16 surrogate split changed")
    ..
..
