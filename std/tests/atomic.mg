mod main

use "std:atomic" as atomic
use "std:errors" as errors

pub main() !void:
    byte := atomic.newU8(10)
    byte.store(20)
    if byte.load() != 20 || byte.exchange(30) != 20 || byte.load() != 30:
        throw errors.failure("u8 atomic operation failed")
    ..
    byte.storeRelease(40)
    if byte.loadAcquire() != 40 || byte.fetchAdd(2) != 40 || byte.fetchSub(1) != 42 || byte.load() != 41:
        throw errors.failure("u8 atomic arithmetic failed")
    ..

    word := atomic.newU32(10)
    word.storeRelease(20)
    if word.loadAcquire() != 20 || word.exchange(30) != 20 || word.fetchAddRelease(2) != 30 || word.fetchSubAcqRel(1) != 32 || word.load() != 31:
        throw errors.failure("u32 atomic operation failed")
    ..

    unsigned := atomic.newU64(10)
    unsigned.store(20)
    if unsigned.load() != 20 || unsigned.exchange(30) != 20 || unsigned.load() != 30:
        throw errors.failure("u64 atomic operation failed")
    ..
    unsigned.storeRelaxed(40)
    if unsigned.loadRelaxed() != 40 || unsigned.fetchAddRelaxed(2) != 40 || unsigned.fetchSub(1) != 42 || unsigned.loadAcquire() != 41:
        throw errors.failure("u64 atomic arithmetic failed")
    ..

    signed := atomic.newI64(-10)
    signed.store(-20)
    if signed.load() != -20 || signed.exchange(-30) != -20 || signed.load() != -30:
        throw errors.failure("i64 atomic operation failed")
    ..
    if signed.fetchAdd(5) != -30 || signed.fetchSub(2) != -25 || signed.load() != -27:
        throw errors.failure("i64 atomic arithmetic failed")
    ..

    floating := atomic.newF64(1.5)
    floating.store(2.5)
    if floating.load() != 2.5 || floating.exchange(3.5) != 2.5 || floating.load() != 3.5:
        throw errors.failure("f64 atomic operation failed")
    ..
..
