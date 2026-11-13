mod main
use "std:errors" as errors
use "std:heap" as heap
use "std:strings" as strings

pub main() !void:
    a := heap.allocator()
    owned := try strings.copy("core")
    if owned.countBytes() != 4:
        owned.free()
        throw errors.failure("primitive string method behavior changed")
    ..
    owned.free()

    # Borrowed literals are ordinary `str` values and carry no destroy duty.
    borrowed str = "literal"
    if borrowed.countBytes() != 7:
        throw errors.failure("borrowed string behavior changed")
    ..
    borrowed.free()

    zero str
    zero.free()
..
