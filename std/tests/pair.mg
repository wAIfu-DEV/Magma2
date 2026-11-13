mod main

use "std:errors" as errors
use "std:pair" as pair

pub main() !void:
    value pair.Pair[u64, bool] = pair.new[u64, bool](42, true)
    if value.first != 42 || value.second == false:
        throw errors.failure("pair construction changed")
    ..

    reversed := pair.Pair[bool, u64](first=false, second=7)
    if reversed.first || reversed.second != 7:
        throw errors.failure("pair fields changed")
    ..
..
