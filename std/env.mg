mod env
# Portable access to the process environment.

use "std:allocator" as allocator
use "std:list" as list

@platform("windows")
use "std:win/env_impl" as impl

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/env_impl" as impl

pub get(name str) !$str:
    a := ctx.alloc
    ret try impl.get(name)
..

pub has(name str) bool:
    ret impl.has(name)
..

pub set(name str, value str) !void:
    try impl.set(name, value)
..

pub unset(name str) !void:
    try impl.unset(name)
..

pub list() !$list.List[str]:
    a := ctx.alloc
    ret try impl.list()
..
