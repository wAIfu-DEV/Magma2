mod env_impl_unix
use "std:allocator" as allocator
use "std:heap" as heap
use "std:strings" as strings
use "std:errors" as errors
use "std:c" as c
use "std:list" as list
use "std:cast" as cast
use "std:llvm" as ll

ext environmentSlot environ ptr

ext ext_getenv getenv(name u8*) u8*
ext ext_setenv setenv(name u8*, value u8*, overwrite c.int) c.int
ext ext_unsetenv unsetenv(name u8*) c.int

environmentPointer() u8**:
    ret cast.reinterpret[u8*](ll.load[ptr](addrof environmentSlot))
..

environmentAt(environment u8**, index u64) u8*:
    # SAFETY: environ is a platform-owned, null-terminated pointer array.
    unsafe:
        ret environment[index]
    ..
..

findValue(name str) u8*:
    if name.countBytes() == 0: ret none ..
    # SAFETY: each environ entry is a null-terminated NAME=VALUE string and
    # the scan stops at the terminating environment pointer.
    unsafe:
        environment := environmentPointer()
        index u64 = 0
        entry := environmentAt(environment, index)
        loop entry != none:
            matched bool = true
            for i u64 = 0 to name.countBytes():
                if entry[i] == 0 || entry[i] != strings.byteAt(name, i):
                    matched = false
                    break
                ..
            ..
            if matched && entry[name.countBytes()] == 61:
                ret cast.utop(cast.ptou(entry) + name.countBytes() + 1)
            ..
            index = index + 1
            entry = environmentAt(environment, index)
        ..
        ret none
    ..
..

pub get(name str) !$str:
    a := ctx.alloc
    value := findValue(name)
    if value == none:
        throw errors.notFound("environment variable was not found")
    ..
    ret try strings.fromCstr(value)
..

pub has(name str) bool:
    ret findValue(name) != none
..

pub set(name str, value str) !void:
    n := try strings.toCstr(name)
    defer heap.allocator().free(n)
    v := try strings.toCstr(value)
    defer heap.allocator().free(v)
    if ext_setenv(n, v, 1) != 0:
        throw errors.failure("setenv failed")
    ..
..

pub unset(name str) !void:
    n := try strings.toCstr(name)
    defer heap.allocator().free(n)
    if ext_unsetenv(n) != 0:
        throw errors.failure("unsetenv failed")
    ..
..

pub list() !$list.List[str]:
    a := ctx.alloc
    entries := try list.new[str](a, fn(value $str) void:
        value.free()
    ..)
    onerror entries.free()
    environment := environmentPointer()
    i u64 = 0
    loop environmentAt(environment, i) != none:
        value str = try strings.fromCstr(environmentAt(environment, i))
        try entries.pushRight(move value)
        i = i + 1
    ..
    ret move entries
..
