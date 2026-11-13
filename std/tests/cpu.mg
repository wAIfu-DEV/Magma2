mod main

use "std:cpu" as cpu
use "std:errors" as errors

pub main() !void:
    if cpu.coreCount() == 0:
        throw errors.failure("CPU core count must be greater than zero")
    ..
..
