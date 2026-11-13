mod main

use "std:allocator" as allocator
use "std:errors" as errors
use "std:fake_alloc" as fake_alloc

pub main() !void:
    a allocator.Allocator = fake_alloc.allocator()
    value u8*, allocErr error = a.alloc(1)
    if value != none || allocErr.code() != errors.failure("").code():
        throw errors.failure("fake allocator did not reject allocation")
    ..

    resized u8*, reallocErr error = a.realloc(none, 1)
    if resized != none || reallocErr.code() != errors.failure("").code():
        throw errors.failure("fake allocator did not reject reallocation")
    ..
    a.free(none)
..
