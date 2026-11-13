mod main
use "std:errors" as errors
use "std:hash" as hash
pub main() !void:
    value := [3]u8
    value[0] = 97
    value[1] = 98
    value[2] = 99
    if hash.string("abc") != hash.string("abc") || hash.bytes(value) != hash.string("abc"):
        throw errors.failure("hash is not deterministic")
    ..
..
