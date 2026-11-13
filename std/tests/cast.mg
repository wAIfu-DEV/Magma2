mod main
use "std:cast" as cast
use "std:errors" as errors
pub main() !void:
    value u64 = 42
    pointer ptr = addrof value
    typed u64* = cast.reinterpret[u64](pointer)
    if *typed != 42 || cast.utop(cast.ptou(pointer)) != pointer:
        throw errors.failure("pointer cast behavior changed")
    ..
    if cast.itou(-1) != 0 - 1 || cast.utoi(7) != 7:
        throw errors.failure("signed cast behavior changed")
    ..
    if cast.u128to64(cast.u64to128(42)) != 42 || cast.i128to64(cast.i64to128(-42)) != -42:
        throw errors.failure("wide cast behavior changed")
    ..
    if cast.itof(-4) != -4.0 || cast.utof(4) != 4.0 || cast.ftoi(-4.0) != -4 || cast.ftou(4.0) != 4:
        throw errors.failure("float cast behavior changed")
    ..
    if cast.i32to64(-7) != -7 || cast.i16to64(-7) != -7 || cast.i8to64(-7) != -7:
        throw errors.failure("signed widening changed")
    ..
    if cast.u32to64(7) != 7 || cast.u16to64(7) != 7 || cast.u8to64(7) != 7:
        throw errors.failure("unsigned widening changed")
    ..
    if cast.u32toi32(7) != 7:
        throw errors.failure("same-width signed conversion changed")
    ..
    if cast.i64to32(-7) != -7 || cast.i64to16(-7) != -7 || cast.i64to8(258) != 2:
        throw errors.failure("signed narrowing changed")
    ..
    if cast.u64to32(7) != 7 || cast.u64to16(65537) != 1 || cast.u64to8(258) != 2:
        throw errors.failure("cast behavior changed")
    ..
..
