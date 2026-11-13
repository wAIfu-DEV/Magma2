mod main

use "std:allocator" as allocator
use "std:builder" as builder
use "std:errors" as errors
use "std:heap" as heap
use "std:strings" as strings
use "std:writer" as writer

pub main() !void:
    a allocator.Allocator = heap.allocator()
    value := try builder.new()
    defer value.free()
    if value.isEmpty() == false || value.byteCount() != 0:
        throw errors.failure("new builder is not empty")
    ..
    try value.ensureCapacity()
    try value.appendBorrowed("checked ")
    try value.appendCopy("builder")
    owned := try strings.copy("!")
    try value.appendOwned(move owned)
    if value.byteCount() != 16 || value.isEmpty():
        throw errors.failure("builder byte count changed")
    ..
    result := try value.build()
    defer result.free()
    if strings.compare(result, "checked builder!") == false:
        throw errors.failure("builder behavior changed")
    ..
    resultPtr u8* = strings.toPtr(result)
    # SAFETY: strings.alloc reserves a trailing terminator after countBytes.
    unsafe:
        if resultPtr[result.countBytes()] != 0:
            throw errors.failure("built string is not null terminated")
        ..
    ..
    try value.reset()
    if value.isEmpty() == false || value.byteCount() != 0:
        throw errors.failure("builder reset changed")
    ..
    output := value.protoBorrow[writer.Writer]()
    temporary := try strings.copy("writer copy")
    writeCount := try output.write(temporary)
    temporary.free()
    if writeCount != 11:
        throw errors.failure("builder writer count changed")
    ..
    written := try value.build()
    defer written.free()
    if strings.compare(written, "writer copy") == false:
        throw errors.failure("builder writer did not copy input")
    ..
    try value.reset()
    try value.addBorrowed("borrowed")
    value.releaseCopies()
    try value.reset()
..
