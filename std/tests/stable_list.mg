mod main

use "std:errors" as errors
use "std:heap" as heap
use "std:stable_list" as stable_list

pub main() !void:
    a := heap.allocator()
    values := try stable_list.new[u64](a, none)
    defer values.free()

    firstIndex := try values.push(41)
    first := try values.get(firstIndex)
    # Nine pages also forces the page-pointer directory itself to grow.
    for i u64 = 1 to 2305:
        index := try values.push(i)
        if index != i:
            throw errors.failure("stable list append returned an incorrect index")
        ..
    ..

    firstAgain := try values.get(firstIndex)
    if first != firstAgain:
        throw errors.failure("stable list moved an element while growing")
    ..
    unsafe:
        if first[0] != 41:
            throw errors.failure("stable list changed a retained element")
        ..
        first[0] = 99
    ..
    zero := try values.get(0)
    unsafe:
        if zero[0] != 99:
            throw errors.failure("stable list pointer did not refer to its element")
        ..
    ..

    last := try values.get(2304)
    unsafe:
        if last[0] != 2304:
            throw errors.failure("stable list returned the wrong element")
        ..
    ..
    if values.count() != 2305:
        throw errors.failure("stable list count is incorrect")
    ..
..
