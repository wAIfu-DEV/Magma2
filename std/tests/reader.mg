mod main
use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:heap" as heap
use "std:reader" as reader
use "std:strings" as strings

Source impl reader.Reader(value u8)

Source.readRaw(bytes u8[], count u64) !u64:
    if count > 0:
        # SAFETY: reader callbacks receive at least count writable elements.
        unsafe:
            bytes[0] = 65
        ..
        ret 1
    ..
    ret 0
..

pub main() !void:
    a allocator.Allocator = heap.allocator()
    source := Source(value=0)
    input := source.protoBorrow[reader.Reader]()
    result := try input.read(1)
    defer result.free()
    if strings.compare(result, "A") == false:
        throw errors.failure("reader behavior changed")
    ..
    resultPtr u8* = strings.toPtr(result)
    # SAFETY: owned strings reserve a terminator immediately after countBytes.
    unsafe:
        if resultPtr[result.countBytes()] != 0:
            throw errors.failure("read string is not null terminated")
        ..
    ..
    buffer := [2]u8
    readCount := try input.readToBuff(buffer, 2)
    if readCount != 1 || buffer[0] != 65:
        throw errors.failure("reader readToBuff changed")
    ..
..
