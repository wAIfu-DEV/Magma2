mod main

use "std:bitset" as bitset
use "std:errors" as errors

pub main() !void:
    value := bitset.BitSet8(bits=0)
    value.set(0, true)
    value.set(7, true)
    if value.get(0) == false || value.get(7) == false || value.get(3):
        throw errors.failure("BitSet8 index access changed")
    ..
    if value.flip(0) || value.get(0):
        throw errors.failure("BitSet8 flip did not clear a set bit")
    ..
    if value.flipBit(4) == false || value.getBit(4) == false:
        throw errors.failure("BitSet8 mask access changed")
    ..
    value.setBit(4, false)
    if value.getBit(4):
        throw errors.failure("BitSet8 mask clear changed")
    ..
..
