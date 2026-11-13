mod hex
# Strict hexadecimal encoding and decoding.

use "std:allocator" as alc
use "std:checked" as checked
use "std:errors" as errors
use "std:slices" as slices
use "std:strings" as strings

pub encodedSize(inputSize u64) !u64:
    ret try checked.uMul(inputSize, 2)
..

pub decodedSize(text str) !u64:
    if (text.countBytes() & 1) != 0:
        throw errors.invalidArgument("hexadecimal input has odd length")
    ..
    ret text.countBytes() / 2
..

digit(nibble u8, uppercase bool) u8:
    if nibble < 10:
        ret 48 + nibble
    ..
    if uppercase:
        ret 65 + nibble - 10
    ..
    ret 97 + nibble - 10
..

decodeNibble(byte u8) !u8:
    if byte >= 48 && byte <= 57:
        ret byte - 48
    ..
    if byte >= 65 && byte <= 70:
        ret byte - 65 + 10
    ..
    if byte >= 97 && byte <= 102:
        ret byte - 97 + 10
    ..
    throw errors.invalidArgument("invalid hexadecimal digit")
..

encodeToCase(input u8[], output u8[], uppercase bool) !u64:
    needed := try encodedSize(slices.count(input))
    if slices.count(output) < needed:
        throw errors.invalidArgument("hexadecimal output buffer is too small")
    ..
    for i u64 = 0 to slices.count(input):
        # encodedSize and the capacity guard establish both affine indices.
        bounded i * 2 < slices.count(output), i * 2 + 1 < slices.count(output):
            output[i * 2] = digit(input[i] >> 4, uppercase)
            output[i * 2 + 1] = digit(input[i] & 0x0F, uppercase)
        ..
    ..
    ret needed
..

pub encodeTo(input u8[], output u8[]) !u64:
    ret try encodeToCase(input, output, false)
..

pub encodeUpperTo(input u8[], output u8[]) !u64:
    ret try encodeToCase(input, output, true)
..

pub decodeTo(text str, output u8[]) !u64:
    needed := try decodedSize(text)
    if slices.count(output) < needed:
        throw errors.invalidArgument("hexadecimal output buffer is too small")
    ..
    input := strings.toPtr(text)
    # SAFETY: decodedSize proves text has exactly needed pairs of bytes; the
    # output capacity guard proves every destination index below needed.
    unsafe:
        for i u64 = 0 to needed:
            high := try decodeNibble(input[i * 2])
            low := try decodeNibble(input[i * 2 + 1])
            output[i] = (high << 4) | low
        ..
    ..
    ret needed
..

encodeAllocated(input u8[], uppercase bool) !$str:
    a := ctx.alloc
    size := try encodedSize(slices.count(input))
    result $str = try strings.alloc(size)
    onerror result.free()
    output u8[] = slices.fromPtr(strings.toPtr(result), size)
    try encodeToCase(input, output, uppercase)
    ret move result
..

pub encode(input u8[]) !$str:
    a := ctx.alloc
    ret try encodeAllocated(input, false)
..

pub encodeUpper(input u8[]) !$str:
    a := ctx.alloc
    ret try encodeAllocated(input, true)
..

pub decode(text str) !$u8[]:
    a := ctx.alloc
    size := try decodedSize(text)
    if size == 0:
        ret slices.fromPtr(none, 0)
    ..
    result := try slices.alloc[u8](size)
    onerror slices.free(result)
    try decodeTo(text, result)
    ret result
..
