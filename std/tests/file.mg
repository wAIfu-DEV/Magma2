mod main
use "std:allocator" as allocator
use "std:file" as file
use "std:heap" as heap
use "std:errors" as errors
use "std:fs" as fs
use "std:context" as context
use "std:thread_pool" as thread_pool
use "std:strings" as strings
pub main() !void:
    a allocator.Allocator = heap.allocator()
    output := try file.open("std_checked_test_file.tmp", file.mode().read().write().create().truncate())
    outputWriter := try output.writer()
    try outputWriter.write("checked")
    if try output.count() != 7 || try output.seek(0, 0) != 0:
        try output.close()
        throw errors.failure("file count or seek changed")
    ..
    outputReader := try output.reader()
    buffer := [7]u8
    if try outputReader.readToBuff(buffer, 7) != 7 || buffer[0] != 99 || buffer[6] != 100:
        try output.close()
        throw errors.failure("file read changed")
    ..
    pool := try thread_pool.new(a, 1, 1, 8, 1)
    ctx = context.new(a, pool.executor())
    pending := try output.readAsync(0, 7)
    asyncContents := try pending.await()
    if strings.compare(asyncContents, "checked") == false:
        asyncContents.free()
        try pool.close()
        try output.close()
        throw errors.failure("positional asynchronous read changed")
    ..
    asyncContents.free()
    try pool.close()
    try output.close()

    # Write access alone must preserve the existing file and must not imply
    # truncation. Opening with truncate makes that destructive intent explicit.
    preserving := try file.open("std_checked_test_file.tmp", file.mode().write())
    preservingWriter := try preserving.writer()
    try preservingWriter.write("x")
    try preserving.close()
    preserved := try file.open("std_checked_test_file.tmp", file.mode().read())
    if try preserved.count() != 7:
        try preserved.close()
        throw errors.failure("write mode unexpectedly truncated the file")
    ..
    try preserved.close()

    truncating := try file.open("std_checked_test_file.tmp", file.mode().write().truncate())
    if try truncating.count() != 0:
        try truncating.close()
        throw errors.failure("truncate mode did not clear the file")
    ..
    try truncating.close()
    try fs.removeFile("std_checked_test_file.tmp")
..
