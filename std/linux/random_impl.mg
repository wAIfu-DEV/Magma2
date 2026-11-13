mod random_impl_linux

use "std:c" as c
use "std:cast" as cast
use "std:errors" as errors
use "std:slices" as slices

ext ext_linux_getrandom getrandom(buffer ptr, count c.size_t, flags c.unsigned_int) i64

pub randomBytes(output u8[]) !void:
    offset u64 = 0
    loop offset < slices.count(output):
        unsafe:
            destination := cast.utop(cast.ptou(slices.toPtr(output)) + offset)
            result := ext_linux_getrandom(destination, slices.count(output) - offset, 0)
            if result <= 0:
                throw errors.failure("operating-system random source failed")
            ..
            offset = offset + cast.itou(result)
        ..
    ..
..
