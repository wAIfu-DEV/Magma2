mod main

use "std:allocator" as allocator
use "std:errors" as errors
use "std:heap" as heap
use "std:linear_map" as linear_map
use "std:cast" as cast
use "std:strings" as strings

pub main() !void:
    a allocator.Allocator = heap.allocator()
    values := try linear_map.new[u64](none)
    defer values.free()
    try values.set("answer", 42)
    answer := try values.get("answer")
    if answer != 42 || values.count() != 1:
        throw errors.failure("linear map behavior changed")
    ..
    keys := values.keysView()
    entries := values.valuesView()
    bounded 0 < keys.count(), 0 < entries.count():
        if try values.indexOf("answer") != 0 || strings.compare(keys[0], "answer") == false || entries[0] != 42:
            throw errors.failure("linear map views changed")
        ..
    ..
    taken := try values.take("answer")
    if taken != 42 || values.count() != 0:
        throw errors.failure("linear map take changed")
    ..
    try values.grow()
    try values.clear()
    if values.count() != 0:
        throw errors.failure("linear map clear changed")
    ..
    try values.set("answer", 42)
    try values.delete("answer")
..
