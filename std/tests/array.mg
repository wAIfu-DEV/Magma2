mod main

use "std:allocator" as allocator
use "std:array" as array
use "std:cast" as cast
use "std:errors" as errors
use "std:heap" as heap

pub main() !void:
    a allocator.Allocator = heap.allocator()
    values := try array.new[u64](a)
    defer values.free(a, none)

    try values.pushRight(a, 10)
    if values.count() != 1:
        throw errors.failure("array right push did not increase count")
    ..
    try values.pushLeft(a, 5)
    if values.count() != 2:
        throw errors.failure("array count changed")
    ..

    taken := try values.popRight(a)
    if taken != 10:
        throw errors.failure("array pop changed")
    ..

    # Force growth in both directions and verify that it preserves order.
    i u64 = 0
    loop i < 16:
        try values.pushRight(a, 100 + i)
        i = i + 1
    ..

    i = 0
    loop i < 16:
        try values.pushLeft(a, 15 - i)
        i = i + 1
    ..

    i = 0
    loop i < 16:
        if try values.get(i) != i:
            throw errors.failure("array left growth changed element order")
        ..
        i = i + 1
    ..

    i = 0
    loop i < 16:
        if try values.get(17 + i) != 100 + i:
            throw errors.failure("array right growth changed element order")
        ..
        i = i + 1
    ..

    rightIdx := try values.expandRight(a)
    if try values.get(rightIdx) != 0:
        throw errors.failure("public right expansion was not zero initialized")
    ..

    try values.expandLeft(a)
    if try values.get(0) != 0:
        throw errors.failure("public left expansion was not zero initialized")
    ..

    zeros := try array.newWithSize[u64](a, 3, 0, 0)
    defer zeros.free(a, none)
    i = 0
    loop i < zeros.count():
        if try zeros.get(i) != 0:
            throw errors.failure("newWithSize was not zero initialized")
        ..
        i = i + 1
    ..

    try zeros.set(a, 0, 42, none)
    try zeros.resize(a, 6, 0, 0, none)
    if try zeros.get(0) != 42:
        throw errors.failure("resize did not preserve an existing value")
    ..
    i = 3
    loop i < zeros.count():
        if try zeros.get(i) != 0:
            throw errors.failure("resize growth was not zero initialized")
        ..
        i = i + 1
    ..
    view := zeros.view()
    bounded 0 < view.count():
        if view[0] != 42:
            throw errors.failure("array view changed")
        ..
    ..
    iterator := zeros.iterator()
    if try iterator.next() != 42:
        throw errors.failure("array iterator changed")
    ..
    takenZero := try zeros.take(0)
    if takenZero != 42 || try zeros.get(0) != 0:
        throw errors.failure("array take changed")
    ..
    replaced := try zeros.replace(1, 9)
    if replaced != 0 || try zeros.get(1) != 9:
        throw errors.failure("array replace changed")
    ..
    try zeros.pushLeft(a, 7)
    if try zeros.popLeft(a) != 7:
        throw errors.failure("array left pop changed")
    ..
    try zeros.clearKeep(a, none)
    if zeros.count() != 0:
        throw errors.failure("array clearKeep changed")
    ..
    try zeros.pushRight(a, 1)
    try zeros.clearShrink(a, none)
    if zeros.count() != 0:
        throw errors.failure("array clearShrink changed")
    ..

    wide := try array.new[u128](a)
    defer wide.free(a, none)
    try wide.pushRight(a, 1)
    wideView := wide.view()
    bounded 0 < wideView.count():
        if cast.ptou(addrof wideView[0]) % 16 != 0:
            throw errors.failure("array element storage is not 16-byte aligned")
        ..
    ..
..
