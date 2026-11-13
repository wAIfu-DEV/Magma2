mod main

use "std:cast" as cast
use "std:checked" as checked
use "std:errors" as errors

expectUOverflow(value u64, err error) !void:
    if err.ok():
        throw errors.failure("expected checked u64 operation to fail")
    ..
..

expectIOverflow(value i64, err error) !void:
    if err.ok():
        throw errors.failure("expected checked i64 operation to fail")
    ..
..

expectU128Overflow(value u128, err error) !void:
    if err.ok():
        throw errors.failure("expected checked u128 operation to fail")
    ..
..

expectI128Overflow(value i128, err error) !void:
    if err.ok():
        throw errors.failure("expected checked i128 operation to fail")
    ..
..

pub main() !void:
    maxU u64 = 0 - 1
    maxI i64 = cast.utoi(maxU >> 1)
    minI i64 = 0 - maxI - 1
    maxU128 u128 = 0 - 1
    maxI128 i128 = 170141183460469231731687303715884105727
    minI128 i128 = 0 - maxI128 - 1

    if try checked.uAdd(20, 22) != 42 || try checked.uSub(50, 8) != 42:
        throw errors.failure("checked unsigned arithmetic changed")
    ..
    if try checked.uMul(6, 7) != 42 || try checked.uDiv(84, 2) != 42:
        throw errors.failure("checked unsigned multiplication or division changed")
    ..
    if try checked.uShl(21, 1) != 42 || try checked.uPow(2, 10) != 1024:
        throw errors.failure("checked unsigned shift or power changed")
    ..
    badUAdd, badUAddErr := checked.uAdd(maxU, 1)
    try expectUOverflow(badUAdd, badUAddErr)
    badUSub, badUSubErr := checked.uSub(0, 1)
    try expectUOverflow(badUSub, badUSubErr)
    badUMul, badUMulErr := checked.uMul(maxU, 2)
    try expectUOverflow(badUMul, badUMulErr)
    badUDiv, badUDivErr := checked.uDiv(1, 0)
    try expectUOverflow(badUDiv, badUDivErr)
    badUShl, badUShlErr := checked.uShl(1, 64)
    try expectUOverflow(badUShl, badUShlErr)

    if try checked.iAdd(-8, 50) != 42 || try checked.iSub(40, -2) != 42:
        throw errors.failure("checked signed arithmetic changed")
    ..
    if try checked.iMul(-6, -7) != 42 || try checked.iDiv(-84, -2) != 42:
        throw errors.failure("checked signed multiplication or division changed")
    ..
    if try checked.iNeg(-42) != 42 || try checked.iPow(-2, 3) != -8:
        throw errors.failure("checked signed negation or power changed")
    ..
    badIAdd, badIAddErr := checked.iAdd(maxI, 1)
    try expectIOverflow(badIAdd, badIAddErr)
    badISub, badISubErr := checked.iSub(minI, 1)
    try expectIOverflow(badISub, badISubErr)
    badIMul, badIMulErr := checked.iMul(minI, -1)
    try expectIOverflow(badIMul, badIMulErr)
    badIDiv, badIDivErr := checked.iDiv(minI, -1)
    try expectIOverflow(badIDiv, badIDivErr)
    badINeg, badINegErr := checked.iNeg(minI)
    try expectIOverflow(badINeg, badINegErr)

    if try checked.u128Add(40, 2) != 42 || try checked.u128Pow(2, 100) == 0:
        throw errors.failure("checked u128 arithmetic changed")
    ..
    badU128Add, badU128AddErr := checked.u128Add(maxU128, 1)
    try expectU128Overflow(badU128Add, badU128AddErr)
    badU128Mul, badU128MulErr := checked.u128Mul(maxU128, 2)
    try expectU128Overflow(badU128Mul, badU128MulErr)
    badU128Shl, badU128ShlErr := checked.u128Shl(1, 128)
    try expectU128Overflow(badU128Shl, badU128ShlErr)

    if try checked.i128Mul(-6, -7) != 42 || try checked.i128Neg(-42) != 42:
        throw errors.failure("checked i128 arithmetic changed")
    ..
    badI128Add, badI128AddErr := checked.i128Add(maxI128, 1)
    try expectI128Overflow(badI128Add, badI128AddErr)
    badI128Mul, badI128MulErr := checked.i128Mul(minI128, -1)
    try expectI128Overflow(badI128Mul, badI128MulErr)
    badI128Div, badI128DivErr := checked.i128Div(minI128, -1)
    try expectI128Overflow(badI128Div, badI128DivErr)

    if try checked.uToU8(255) != 255 || try checked.iToI8(-128) != -128:
        throw errors.failure("checked narrow conversion changed")
    ..
    badNarrow, badNarrowErr := checked.uToU8(256)
    if badNarrowErr.ok():
        throw errors.failure("checked unsigned narrowing accepted overflow")
    ..
    badSign, badSignErr := checked.iToU(-1)
    if badSignErr.ok():
        throw errors.failure("checked signedness conversion accepted a negative value")
    ..
    if try checked.u128ToU(42) != 42 || try checked.i128ToI(-42) != -42:
        throw errors.failure("checked 128-bit narrowing changed")
    ..

    if try checked.byteCount[u32](10) != 40:
        throw errors.failure("checked byte count changed")
    ..
    if try checked.addByteCount(2, 10, 4) != 42 || try checked.elementCount(40, 4) != 10:
        throw errors.failure("checked size helper changed")
    ..
    if try checked.alignUp(33, 16) != 48 || try checked.alignDown(47, 16) != 32:
        throw errors.failure("checked alignment changed")
    ..
    if checked.isAligned(48, 16) == false || checked.isAligned(48, 3):
        throw errors.failure("alignment predicate changed")
    ..
    badAlignOverflow, badAlignOverflowErr := checked.alignUp(maxU, 16)
    try expectUOverflow(badAlignOverflow, badAlignOverflowErr)
    badAlignment, badAlignmentErr := checked.alignUp(1, 3)
    try expectUOverflow(badAlignment, badAlignmentErr)
..
