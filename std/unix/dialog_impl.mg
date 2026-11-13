mod dialog_impl_unix
# XDG Desktop Portal backend boundary. The D-Bus implementation is pending;
# keeping it behind this module preserves the portable API.

use "std:allocator" as allocator
use "std:errors" as errors

pub openFile(filters ptr, filterCount u64, defaultPath str, title str, parent ptr) !$str:
    a := ctx.alloc
    throw errors.failure("XDG file dialog backend is not implemented")
..

pub saveFile(filters ptr, filterCount u64, defaultPath str, defaultName str, title str, parent ptr) !$str:
    a := ctx.alloc
    throw errors.failure("XDG file dialog backend is not implemented")
..

pub openDir(defaultPath str, title str, parent ptr) !$str:
    a := ctx.alloc
    throw errors.failure("XDG file dialog backend is not implemented")
..
