mod main
use "std:flag" as flag
use "std:heap" as heap
use "std:strings" as strings
use "std:errors" as errors
use "std:array" as array

pub main() !void:
    parser := try flag.new(heap.allocator(), "tool")
    defer parser.free()
    verbose bool = false
    jobs u64 = 1
    output str
    quiet bool = false
    numbers := try array.new[u64](heap.allocator())
    defer numbers.free(heap.allocator(), none)
    try parser.boolean("verbose", 118, addrof verbose, "verbose output")
    try parser.unsigned("jobs", 106, addrof jobs, "worker count")
    try parser.string("output", 111, addrof output, "output path")
    try parser.boolean("quiet", 113, addrof quiet, "quiet output")
    try parser.unsigneds("number", 110, addrof numbers, "repeated number")
    input := [8]str
    input[0] = "-vq"
    input[1] = "-j"
    input[2] = "4"
    input[3] = "--output=result"
    input[4] = "-n2"
    input[5] = "--number"
    input[6] = "3"
    input[7] = "source"
    result := try parser.parse(input)
    defer result.free()
    values := result.positionals()
    if verbose == false || quiet == false || jobs != 4 || strings.compare(output, "result") == false:
        throw errors.failure("typed flag parsing changed")
    ..
    if values.count() != 1 || strings.compare(values[0], "source") == false:
        throw errors.failure("positional parsing changed")
    ..
    numberValues := numbers.view()
    if numbers.count() != 2 || numberValues[0] != 2 || numberValues[1] != 3:
        throw errors.failure("repeated numeric flags changed")
    ..
    usage := try parser.usage()
    defer usage.free()
    position u64, findError error = strings.find(usage, "--verbose")
    if findError.nok():
        throw errors.failure("allocated usage omitted option")
    ..
..
