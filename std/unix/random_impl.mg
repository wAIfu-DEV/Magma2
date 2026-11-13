mod random_impl_unix

use "std:c" as c
use "std:slices" as slices

ext ext_unix_arc4random_buf arc4random_buf(buffer ptr, count c.size_t) void

pub randomBytes(output u8[]) !void:
    ext_unix_arc4random_buf(slices.toPtr(output), slices.count(output))
..
