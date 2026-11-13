mod sha1
# SHA-1 digest support for protocols that still require it, such as the
# WebSocket opening handshake. Do not use SHA-1 for signatures or new
# cryptographic designs.

use "std:cast" as cast
use "std:errors" as errors
use "std:slices" as slices

pub const DIGEST_BYTES u64 = 20

rotateLeft(value u32, count u32) u32:
    ret (value << count) | (value >> (32 - count))
..

readWord(input u8[], offset u64) u32:
    unsafe:
        value := cast.u64to32(cast.u8to64(input[offset])) << 24
        value = value | (cast.u64to32(cast.u8to64(input[offset + 1])) << 16)
        value = value | (cast.u64to32(cast.u8to64(input[offset + 2])) << 8)
        ret value | cast.u64to32(cast.u8to64(input[offset + 3]))
    ..
..

processBlock(block u8[], state u32*) void:
    words := [80]u32
    for i u64 = 0 to 16:
        words[i] = readWord(block, i * 4)
    ..
    for i u64 = 16 to 80:
        bounded i < 80, i - 3 < 80, i - 8 < 80, i - 14 < 80, i - 16 < 80:
            words[i] = rotateLeft(words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16], 1)
        ..
    ..

    unsafe:
        a := state[0]
        b := state[1]
        c := state[2]
        d := state[3]
        e := state[4]
        for i u64 = 0 to 80:
            f u32 = 0
            k u32 = 0
            if i < 20:
                f = (b & c) | ((b ^ 4294967295) & d)
                k = 1518500249
            elif i < 40:
                f = b ^ c ^ d
                k = 1859775393
            elif i < 60:
                f = (b & c) | (b & d) | (c & d)
                k = 2400959708
            else:
                f = b ^ c ^ d
                k = 3395469782
            ..
            temporary := rotateLeft(a, 5) + f + e + k + words[i]
            e = d
            d = c
            c = rotateLeft(b, 30)
            b = a
            a = temporary
        ..
        state[0] = state[0] + a
        state[1] = state[1] + b
        state[2] = state[2] + c
        state[3] = state[3] + d
        state[4] = state[4] + e
    ..
..

# Computes a SHA-1 digest into exactly 20 caller-owned bytes.
pub sum(input u8[]) !$u8[]:
    output u8[] = try slices.alloc[u8](20)

    state := [5]u32
    state[0] = 1732584193
    state[1] = 4023233417
    state[2] = 2562383102
    state[3] = 271733878
    state[4] = 3285377520

    count := slices.count(input)
    offset u64 = 0
    loop offset + 64 <= count:
        block u8[] = slices.fromPtr(cast.reinterpret[u8](cast.utop(cast.ptou(slices.toPtr(input)) + offset)), 64)
        processBlock(block, cast.reinterpret[u32](slices.toPtr(state)))
        offset = offset + 64
    ..

    tail := [128]u8
    remaining := count - offset
    for i u64 = 0 to remaining:
        bounded i < 128, offset + i < slices.count(input):
            tail[i] = input[offset + i]
        ..
    ..
    bounded remaining < 128:
        tail[remaining] = 128
    ..
    padded u64 = 64
    if remaining >= 56:
        padded = 128
    ..
    bitLength := count * 8
    for i u64 = 0 to 8:
        bounded padded - 1 - i < 128:
            tail[padded - 1 - i] = cast.u64to8(bitLength >> cast.u64to32(i * 8))
        ..
    ..
    first u8[] = slices.fromPtr(slices.toPtr(tail), 64)
    processBlock(first, cast.reinterpret[u32](slices.toPtr(state)))
    if padded == 128:
        second u8[] = slices.fromPtr(cast.reinterpret[u8](cast.utop(cast.ptou(slices.toPtr(tail)) + 64)), 64)
        processBlock(second, cast.reinterpret[u32](slices.toPtr(state)))
    ..

    for i u64 = 0 to 5:
        word := state[i]
        bounded i * 4 < slices.count(output), i * 4 + 1 < slices.count(output), i * 4 + 2 < slices.count(output), i * 4 + 3 < slices.count(output):
            output[i * 4] = cast.u64to8(cast.u32to64(word >> 24))
            output[i * 4 + 1] = cast.u64to8(cast.u32to64(word >> 16))
            output[i * 4 + 2] = cast.u64to8(cast.u32to64(word >> 8))
            output[i * 4 + 3] = cast.u64to8(cast.u32to64(word))
        ..
    ..
    ret output
..
