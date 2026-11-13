mod main
use "std:args" as args
use "std:errors" as errors
use "std:strings" as strings

pub main() !void:
    raw := [3]str
    raw[0] = "tool"
    raw[1] = "first"
    raw[2] = ""
    parsed := args.new(raw)
    if parsed.count() != 2 || strings.compare(try parsed.executable(), "tool") == false:
        throw errors.failure("args header changed")
    ..
    if strings.compare(try parsed.get(0), "first") == false || (try parsed.get(1)).countBytes() != 0:
        throw errors.failure("args values changed")
    ..
..
