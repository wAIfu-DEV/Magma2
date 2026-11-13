mod percent
# Percent encoding with explicit URI-component, path-segment, and form policies.

use "std:allocator" as alc
use "std:checked" as checked
use "std:errors" as errors
use "std:slices" as slices
use "std:strings" as strings

pub const URI_COMPONENT u8 = 1
pub const PATH_SEGMENT u8 = 2
pub const FORM u8 = 3

unreserved(byte u8) bool:
    ret (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45 || byte == 46 || byte == 95 || byte == 126
..

pathAllowed(byte u8) bool:
    if unreserved(byte):
        ret true
    ..
    ret byte == 33 || byte == 36 || byte == 38 || byte == 39 || byte == 40 || byte == 41 || byte == 42 || byte == 43 || byte == 44 || byte == 59 || byte == 61 || byte == 58 || byte == 64
..

allowed(byte u8, policy u8) !bool:
    if policy == URI_COMPONENT || policy == FORM:
        ret unreserved(byte)
    ..
    if policy == PATH_SEGMENT:
        ret pathAllowed(byte)
    ..
    throw errors.invalidArgument("invalid percent-encoding policy")
..

hexDigit(nibble u8) u8:
    if nibble < 10:
        ret 48 + nibble
    ..
    ret 65 + nibble - 10
..

hexValue(byte u8) !u8:
    if byte >= 48 && byte <= 57:
        ret byte - 48
    ..
    if byte >= 65 && byte <= 70:
        ret byte - 65 + 10
    ..
    if byte >= 97 && byte <= 102:
        ret byte - 97 + 10
    ..
    throw errors.invalidArgument("invalid percent escape")
..

pub encodedSize(text str, policy u8) !u64:
    input := strings.toPtr(text)
    total u64 = 0
    # SAFETY: input is the byte pointer for text and the loop is bounded by its
    # exact byte count.
    unsafe:
        for i u64 = 0 to text.countBytes():
            byte := input[i]
            if (policy == FORM && byte == 32) || try allowed(byte, policy):
                total = try checked.uAdd(total, 1)
            else:
                total = try checked.uAdd(total, 3)
            ..
        ..
    ..
    ret total
..

pub encodeTo(text str, output u8[], policy u8) !u64:
    needed := try encodedSize(text, policy)
    if slices.count(output) < needed:
        throw errors.invalidArgument("percent output buffer is too small")
    ..
    input := strings.toPtr(text)
    inputIndex u64 = 0
    outputIndex u64 = 0
    # SAFETY: input spans text.countBytes; encodedSize and the capacity guard
    # bound the one- or three-byte output produced per input byte.
    unsafe:
      loop inputIndex < text.countBytes():
        byte := input[inputIndex]
        if policy == FORM && byte == 32:
            output[outputIndex] = 43
            outputIndex = outputIndex + 1
        elif try allowed(byte, policy):
            output[outputIndex] = byte
            outputIndex = outputIndex + 1
        else:
            output[outputIndex] = 37
            output[outputIndex + 1] = hexDigit(byte >> 4)
            output[outputIndex + 2] = hexDigit(byte & 15)
            outputIndex = outputIndex + 3
        ..
          inputIndex = inputIndex + 1
      ..
    ..
    ret outputIndex
..

pub encode(text str, policy u8) !$str:
    a := ctx.alloc
    size := try encodedSize(text, policy)
    result $str = try strings.alloc(size)
    onerror result.free()
    output u8[] = slices.fromPtr(strings.toPtr(result), size)
    try encodeTo(text, output, policy)
    ret move result
..

decodedSizeKind(text str, form bool) !u64:
    input := strings.toPtr(text)
    total u64 = 0
    i u64 = 0
    # SAFETY: input spans text.countBytes; the truncation guard precedes both
    # lookahead bytes of every percent escape.
    unsafe:
      loop i < text.countBytes():
        if input[i] == 37:
            if i + 2 >= text.countBytes():
                throw errors.invalidArgument("truncated percent escape")
            ..
            high := try hexValue(input[i + 1])
            low := try hexValue(input[i + 2])
            i = i + 3
        else:
            i = i + 1
        ..
          total = try checked.uAdd(total, 1)
      ..
    ..
    ret total
..

pub decodedSize(text str) !u64:
    ret try decodedSizeKind(text, false)
..

decodeToKind(text str, output u8[], form bool) !u64:
    needed := try decodedSizeKind(text, form)
    if slices.count(output) < needed:
        throw errors.invalidArgument("percent-decoded output buffer is too small")
    ..
    input := strings.toPtr(text)
    inputIndex u64 = 0
    outputIndex u64 = 0
    # SAFETY: decodedSizeKind validates escape lookahead and needed bounds the
    # destination; each iteration produces exactly one output byte.
    unsafe:
      loop inputIndex < text.countBytes():
        byte := input[inputIndex]
        if byte == 37:
            high := try hexValue(input[inputIndex + 1])
            low := try hexValue(input[inputIndex + 2])
            output[outputIndex] = (high << 4) | low
            inputIndex = inputIndex + 3
        else:
            if form && byte == 43:
                output[outputIndex] = 32
            else:
                output[outputIndex] = byte
            ..
            inputIndex = inputIndex + 1
        ..
          outputIndex = outputIndex + 1
      ..
    ..
    ret outputIndex
..

pub decodeTo(text str, output u8[]) !u64:
    ret try decodeToKind(text, output, false)
..

pub decodeFormTo(text str, output u8[]) !u64:
    ret try decodeToKind(text, output, true)
..

decodeAllocated(text str, form bool) !$u8[]:
    a := ctx.alloc
    size := try decodedSizeKind(text, form)
    if size == 0:
        ret slices.fromPtr(none, 0)
    ..
    result := try slices.alloc[u8](size)
    onerror slices.free(result)
    try decodeToKind(text, result, form)
    ret result
..

pub decode(text str) !$u8[]:
    a := ctx.alloc
    ret try decodeAllocated(text, false)
..

pub decodeForm(text str) !$u8[]:
    a := ctx.alloc
    ret try decodeAllocated(text, true)
..
