mod main
use "std:errors" as errors
use "std:search" as search
pub main() !void:
    values := [3]u64
    values[0] = 2
    values[1] = 4
    values[2] = 6
    compare := fn(a u64, b u64) i64:
        if a < b:
            ret -1
        elif a > b:
            ret 1
        ..
        ret 0
    ..
    linear := try search.linear[u64](values, 4, compare)
    binary := try search.binary[u64](values, 6, compare)
    if linear != 1 || binary != 2:
        throw errors.failure("search behavior changed")
    ..
..
