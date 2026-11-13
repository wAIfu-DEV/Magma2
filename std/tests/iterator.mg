mod main
use "std:errors" as errors
use "std:iterator" as iterator
pub main() !void:
    values := iterator.new[u64](none, fn(impl ptr, index u64) bool:
        ret index < 2
    .., fn(impl ptr, index u64) !u64:
        ret index + 10
    ..)
    first := try values.next()
    if first != 10 || values.hasData() == false:
        throw errors.failure("iterator behavior changed")
    ..
..
