mod main
use "std:errors" as errors
use "std:heap" as heap
use "std:hex" as hex
use "std:slices" as slices
use "std:strings" as strings

pub main() !void:
    a := heap.allocator()
    input := [3]u8
    input[0] = 0
    input[1] = 0xAB
    input[2] = 0xFF
    view u8[] = slices.fromPtr(slices.toPtr(input), 3)
    encoded := try hex.encode(view)
    defer encoded.free()
    if strings.compare(encoded, "00abff") == false:
        throw errors.failure("hexadecimal encoding changed")
    ..
    decoded := try hex.decode("00ABff")
    defer slices.free(decoded)
    if slices.count(decoded) != 3 || decoded[1] != 0xAB || decoded[2] != 0xFF:
        throw errors.failure("hexadecimal decoding changed")
    ..
    bad, badError := hex.decode("abc")
    if badError.ok():
        slices.free(bad)
        throw errors.failure("odd hexadecimal input accepted")
    ..
..
