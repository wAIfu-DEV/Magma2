mod base64
# Strict padded Base64 encoding and decoding.

use "std:allocator" as alc
use "std:checked" as checked
use "std:errors" as errors
use "std:slices" as slices
use "std:strings" as strings

pub encodedSize(inputSize u64) !u64:
    groups := try checked.uDiv(try checked.uAdd(inputSize, 2), 3)
    ret try checked.uMul(groups, 4)
..

alphabet(value u8, urlSafe bool) u8:
    if value < 26:
        ret 65 + value
    ..
    if value < 52:
        ret 97 + value - 26
    ..
    if value < 62:
        ret 48 + value - 52
    ..
    if value == 62:
        if urlSafe:
            ret 45
        ..
        ret 43
    ..
    if urlSafe:
        ret 95
    ..
    ret 47
..

decodeValue(byte u8, urlSafe bool) !u8:
    if byte >= 65 && byte <= 90:
        ret byte - 65
    ..
    if byte >= 97 && byte <= 122:
        ret byte - 97 + 26
    ..
    if byte >= 48 && byte <= 57:
        ret byte - 48 + 52
    ..
    if urlSafe && byte == 45:
        ret 62
    ..
    if urlSafe && byte == 95:
        ret 63
    ..
    if urlSafe == false && byte == 43:
        ret 62
    ..
    if urlSafe == false && byte == 47:
        ret 63
    ..
    throw errors.invalidArgument("invalid Base64 character")
..

decodedSizeFor(text str, urlSafe bool) !u64:
    count := text.countBytes()
    if count == 0:
        ret 0
    ..
    if (count & 3) != 0:
        throw errors.invalidArgument("padded Base64 length is not a multiple of four")
    ..
    input := strings.toPtr(text)
    padding u64 = 0
    # SAFETY: nonzero, four-byte-aligned count is at least four; input points
    # to all count bytes of text and padding never exceeds two.
    unsafe:
        if input[count - 1] == 61:
            padding = 1
            if input[count - 2] == 61:
                padding = 2
            ..
        ..
        for i u64 = 0 to count - padding:
            ignored := try decodeValue(input[i], urlSafe)
        ..
        for i u64 = count - padding to count:
            if input[i] != 61:
                throw errors.invalidArgument("Base64 padding is misplaced")
            ..
        ..
    ..
    size := try checked.uMul(count / 4, 3)
    ret try checked.uSub(size, padding)
..

pub decodedSize(text str) !u64:
    ret try decodedSizeFor(text, false)
..

pub decodedUrlSize(text str) !u64:
    ret try decodedSizeFor(text, true)
..

encodeToKind(input u8[], output u8[], urlSafe bool) !u64:
    needed := try encodedSize(slices.count(input))
    if slices.count(output) < needed:
        throw errors.invalidArgument("Base64 output buffer is too small")
    ..
    inputIndex u64 = 0
    outputIndex u64 = 0
    count := slices.count(input)
    loop inputIndex + 3 <= count:
        # Three input bytes map to four output bytes; encodedSize and the
        # capacity guard establish the output predicates.
        bounded inputIndex < count, inputIndex + 1 < count, inputIndex + 2 < count, outputIndex < slices.count(output), outputIndex + 1 < slices.count(output), outputIndex + 2 < slices.count(output), outputIndex + 3 < slices.count(output):
            a := input[inputIndex]
            b := input[inputIndex + 1]
            c := input[inputIndex + 2]
            output[outputIndex] = alphabet(a >> 2, urlSafe)
            output[outputIndex + 1] = alphabet(((a & 3) << 4) | (b >> 4), urlSafe)
            output[outputIndex + 2] = alphabet(((b & 15) << 2) | (c >> 6), urlSafe)
            output[outputIndex + 3] = alphabet(c & 63, urlSafe)
        ..
        inputIndex = inputIndex + 3
        outputIndex = outputIndex + 4
    ..
    remaining := count - inputIndex
    if remaining == 1:
        bounded inputIndex < count, outputIndex < slices.count(output), outputIndex + 1 < slices.count(output), outputIndex + 2 < slices.count(output), outputIndex + 3 < slices.count(output):
            a := input[inputIndex]
            output[outputIndex] = alphabet(a >> 2, urlSafe)
            output[outputIndex + 1] = alphabet((a & 3) << 4, urlSafe)
            output[outputIndex + 2] = 61
            output[outputIndex + 3] = 61
        ..
    elif remaining == 2:
        bounded inputIndex < count, inputIndex + 1 < count, outputIndex < slices.count(output), outputIndex + 1 < slices.count(output), outputIndex + 2 < slices.count(output), outputIndex + 3 < slices.count(output):
            a := input[inputIndex]
            b := input[inputIndex + 1]
            output[outputIndex] = alphabet(a >> 2, urlSafe)
            output[outputIndex + 1] = alphabet(((a & 3) << 4) | (b >> 4), urlSafe)
            output[outputIndex + 2] = alphabet((b & 15) << 2, urlSafe)
            output[outputIndex + 3] = 61
        ..
    ..
    ret needed
..

pub encodeTo(input u8[], output u8[]) !u64:
    ret try encodeToKind(input, output, false)
..

pub encodeUrlTo(input u8[], output u8[]) !u64:
    ret try encodeToKind(input, output, true)
..

decodeToKind(text str, output u8[], urlSafe bool) !u64:
    needed := try decodedSizeFor(text, urlSafe)
    if slices.count(output) < needed:
        throw errors.invalidArgument("Base64 output buffer is too small")
    ..
    input := strings.toPtr(text)
    inputIndex u64 = 0
    outputIndex u64 = 0
    count := text.countBytes()
    # SAFETY: decodedSizeFor validates four-byte groups and padding; needed and
    # its capacity guard bound every produced output byte.
    unsafe:
      loop inputIndex < count:
        a := try decodeValue(input[inputIndex], urlSafe)
        b := try decodeValue(input[inputIndex + 1], urlSafe)
        thirdPadding := input[inputIndex + 2] == 61
        fourthPadding := input[inputIndex + 3] == 61
        c u8 = 0
        d u8 = 0
        if thirdPadding == false:
            c = try decodeValue(input[inputIndex + 2], urlSafe)
        ..
        if fourthPadding == false:
            d = try decodeValue(input[inputIndex + 3], urlSafe)
        ..
        if thirdPadding && fourthPadding == false:
            throw errors.invalidArgument("Base64 padding is misplaced")
        ..
        if thirdPadding && (b & 15) != 0:
            throw errors.invalidArgument("Base64 has non-zero trailing bits")
        ..
        if fourthPadding && thirdPadding == false && (c & 3) != 0:
            throw errors.invalidArgument("Base64 has non-zero trailing bits")
        ..
        output[outputIndex] = (a << 2) | (b >> 4)
        outputIndex = outputIndex + 1
        if thirdPadding == false:
            output[outputIndex] = (b << 4) | (c >> 2)
            outputIndex = outputIndex + 1
        ..
        if fourthPadding == false:
            output[outputIndex] = (c << 6) | d
            outputIndex = outputIndex + 1
        ..
          inputIndex = inputIndex + 4
      ..
    ..
    ret outputIndex
..

pub decodeTo(text str, output u8[]) !u64:
    ret try decodeToKind(text, output, false)
..

pub decodeUrlTo(text str, output u8[]) !u64:
    ret try decodeToKind(text, output, true)
..

encodeAllocated(input u8[], urlSafe bool) !$str:
    a := ctx.alloc
    size := try encodedSize(slices.count(input))
    result $str = try strings.alloc(size)
    onerror result.free()
    output u8[] = slices.fromPtr(strings.toPtr(result), size)
    try encodeToKind(input, output, urlSafe)
    ret move result
..

pub encode(input u8[]) !$str:
    a := ctx.alloc
    ret try encodeAllocated(input, false)
..

pub encodeUrl(input u8[]) !$str:
    a := ctx.alloc
    ret try encodeAllocated(input, true)
..

decodeAllocated(text str, urlSafe bool) !$u8[]:
    a := ctx.alloc
    size := try decodedSizeFor(text, urlSafe)
    if size == 0:
        ret slices.fromPtr(none, 0)
    ..
    result := try slices.alloc[u8](size)
    onerror slices.free(result)
    try decodeToKind(text, result, urlSafe)
    ret result
..

pub decode(text str) !$u8[]:
    a := ctx.alloc
    ret try decodeAllocated(text, false)
..

pub decodeUrl(text str) !$u8[]:
    a := ctx.alloc
    ret try decodeAllocated(text, true)
..
