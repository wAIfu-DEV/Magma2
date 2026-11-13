mod main
use "std:allocator" as allocator
use "std:errors" as errors
use "std:heap" as heap
use "std:strconv" as strconv
use "std:strings" as strings
pub main() !void:
    a allocator.Allocator = heap.allocator()
    number := try strconv.parseUint("42")
    boolean := try strconv.parseBool("true")
    if number != 42 || boolean == false:
        throw errors.failure("strconv parse changed")
    ..
    formatted := try strconv.formatUint(42)
    defer formatted.free()
    if strings.compare(formatted, "42") == false:
        throw errors.failure("strconv format changed")
    ..
    formattedPtr u8* = strings.toPtr(formatted)
    # SAFETY: owned strings reserve a terminator immediately after countBytes.
    unsafe:
        if formattedPtr[formatted.countBytes()] != 0:
            throw errors.failure("formatted string is not null terminated")
        ..
    ..
..
