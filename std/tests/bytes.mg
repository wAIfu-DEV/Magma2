mod main
use "std:bytes" as bytes
use "std:errors" as errors
pub main() !void:
    value := [3]u8
    value[0] = 1
    value[1] = 2
    value[2] = 3
    index := try bytes.indexByte(value, 2)
    if index != 1 || bytes.contains(value, 3) == false || bytes.equal(value, value) == false:
        throw errors.failure("bytes search changed")
    ..
    prefix := [2]u8
    prefix[0] = 1
    prefix[1] = 2
    suffix := [2]u8
    suffix[0] = 2
    suffix[1] = 3
    if bytes.startsWith(value, prefix) == false || bytes.endsWith(value, suffix) == false:
        throw errors.failure("bytes prefix or suffix changed")
    ..
    iterator := bytes.iterator(addrof value)
    first := try iterator.next()
    if first != 1:
        throw errors.failure("bytes iterator changed")
    ..
    bytes.reverse(value)
    if value[0] != 3 || value[2] != 1:
        throw errors.failure("bytes reverse changed")
    ..
..
