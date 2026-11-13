mod main

use "std:allocator" as allocator
use "std:errors" as errors
use "std:heap" as heap
use "std:list" as list
use "std:array" as array
use "std:cast" as cast

pub main() !void:
    a allocator.Allocator = heap.allocator()
    values := try list.new[u64](a, none)
    defer values.free()
    try values.pushRight(4)
    try values.pushLeft(2)
    taken := try values.popRight()
    if taken != 4 || values.count() != 1:
        throw errors.failure("list behavior changed")
    ..
    backing := try array.new[u64](a)
    try backing.pushRight(a, 10)
    converted := list.fromArray[u64](a, move backing, none)
    defer converted.free()
    if converted.count() != 1 || try converted.get(0) != 10:
        throw errors.failure("list fromArray changed")
    ..
    try converted.set(0, 11)
    convertedView := converted.view()
    bounded 0 < convertedView.count():
        if convertedView[0] != 11 || try converted.take(0) != 11:
            throw errors.failure("list set, view, or take changed")
        ..
    ..
    try converted.pushRight(12)
    replaced := try converted.replace(0, 13)
    if replaced != 0 || try converted.get(0) != 13:
        throw errors.failure("list replace changed")
    ..
    try converted.resize(2, 1, 1)
    try converted.expandLeft()
    right := try converted.expandRight()
    if converted.count() != 4 || right != 3:
        throw errors.failure("list resize or expand changed")
    ..
    iterator := converted.iterator()
    first := try iterator.next()
    try converted.clearKeep()
    if converted.count() != 0:
        throw errors.failure("list clearKeep changed")
    ..
    try converted.pushRight(1)
    try converted.pushLeft(2)
    if try converted.popLeft() != 2:
        throw errors.failure("list popLeft changed")
    ..
    try converted.clearShrink()
    if converted.count() != 0:
        throw errors.failure("list clearShrink changed")
    ..
..
