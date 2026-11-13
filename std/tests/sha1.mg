mod main

use "std:sha1" as sha1
use "std:errors" as errors
use "std:slices" as slices
use "std:strings" as strings

hexDigit(value u8) u8:
    if value < 10:
        ret 48 + value
    ..
    ret 97 + value - 10
..

pub main() !void:
    a := ctx.alloc
    input u8[] = slices.fromPtr(strings.toPtr("abc"), 3)
    digest := try sha1.sum(input)
    defer a.free(slices.toPtr(digest))
    encoded := [40]u8
    for i u64 = 0 to 20:
        bounded i < slices.count(digest), i * 2 < 40, i * 2 + 1 < 40:
            encoded[i * 2] = hexDigit(digest[i] >> 4)
            encoded[i * 2 + 1] = hexDigit(digest[i] & 15)
        ..
    ..
    actual := strings.fromPtrNoCopy(slices.toPtr(encoded), 40)
    if strings.compare(actual, "a9993e364706816aba3e25717850c26c9cd0d89d") == false:
        throw errors.failure("SHA-1 digest changed")
    ..
..
