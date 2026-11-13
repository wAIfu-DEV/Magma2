mod main
use "std:duplex" as duplex
use "std:errors" as errors

Stream impl duplex.Duplex(value u8)

Stream.writeRaw(bytes str) !u64:
    ret bytes.countBytes()
..

Stream.readRaw(bytes u8[], count u64) !u64:
    ret 0
..

pub main() !void:
    implementation := Stream(value=0)
    stream := implementation.protoBorrow[duplex.Duplex]()
    count := try stream.writer().write("ok")
    if count != 2:
        throw errors.failure("duplex behavior changed")
    ..
    buffer := [1]u8
    if try stream.reader().readToBuff(buffer, 1) != 0:
        throw errors.failure("duplex reader changed")
    ..
..
