mod main
use "std:errors" as errors
use "std:random" as random
use "std:slices" as slices
pub main() !void:
    first := random.new(123)
    second := random.new(123)
    if first.next() != second.next() || first.below(10) >= 10 || first.bool() != second.bool():
        throw errors.failure("random behavior changed")
    ..
    output := [32]u8
    view u8[] = slices.fromPtr(slices.toPtr(output), 32)
    try random.bytesTo(view)
    allocated := try random.bytes(32)
    defer slices.free(allocated)
    if slices.count(allocated) != 32:
        throw errors.failure("random byte count changed")
    ..
    if try random.below(10) >= 10:
        throw errors.failure("operating-system random value is out of bounds")
    ..
    ignored := try random.next()
    ignoredBool := try random.bool()
    operatingSystem := random.os()
    if try operatingSystem.below(10) >= 10:
        throw errors.failure("operating-system generator value is out of bounds")
    ..
    ignored = try operatingSystem.next()
    ignoredBool = try operatingSystem.bool()
..
