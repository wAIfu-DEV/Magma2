mod main
use "std:allocator" as allocator
use "std:heap" as heap
use "std:io" as io
pub main() !void:
    a allocator.Allocator = heap.allocator()
    rawOutput := io.stdoutUnbuffered()
    try rawOutput.write("")
    rawError := io.stderrUnbuffered()
    try rawError.write("")
    rawInput := io.stdinUnbuffered()
    output := try io.stdout()
    try output.writer().write("")
    try output.close()
    errorOutput := try io.stderr()
    try errorOutput.writer().write("")
    try errorOutput.close()
    input := try io.stdin()
    input.close()
..
