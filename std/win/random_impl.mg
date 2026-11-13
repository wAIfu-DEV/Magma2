mod random_impl_win

use "std:c" as c
use "std:errors" as errors
use "std:slices" as slices

link "bcrypt"

ext ext_win_BCryptGenRandom BCryptGenRandom(algorithm ptr, buffer u8*, count c.unsigned_long, flags c.unsigned_long) i32

pub randomBytes(output u8[]) !void:
    if slices.count(output) > 4294967295:
        throw errors.wouldOverflow("random byte request is too large")
    ..
    if ext_win_BCryptGenRandom(none, slices.toPtr(output), slices.count(output), 2) < 0:
        throw errors.failure("operating-system random source failed")
    ..
..
