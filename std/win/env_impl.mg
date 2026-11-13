mod env_impl_win
use "std:allocator" as allocator
use "std:win/types" as win
use "std:heap" as heap
use "std:utf8" as utf8
use "std:utf16" as utf16
use "std:slices" as slices
use "std:errors" as errors
use "std:c" as c
use "std:list" as list
use "std:cast" as cast

ext ext_GetEnvironmentVariableW GetEnvironmentVariableW(name win.LPCWSTR, value win.LPWSTR, size win.DWORD) win.DWORD
ext ext_SetEnvironmentVariableW SetEnvironmentVariableW(name win.LPCWSTR, value win.LPCWSTR) win.BOOL
ext ext_GetLastError GetLastError() win.DWORD
ext ext_GetEnvironmentStringsW GetEnvironmentStringsW() win.LPWSTR
ext ext_FreeEnvironmentStringsW FreeEnvironmentStringsW(block win.LPWSTR) win.BOOL

name16(name str) !$u16[]:
    ret try utf8.utf8To16NT(name)
..

pub get(name str) !$str:
    temporary := ctx.alloc
    wide := try name16(name)
    defer heap.allocator().free(slices.toPtr(wide))
    local := [256]u16
    written := ext_GetEnvironmentVariableW(cast.reinterpret[u16](slices.toPtr(wide)), cast.reinterpret[u16](slices.toPtr(local)), 256)
    if written == 0:
        code := ext_GetLastError()
        if code == 203:
            throw errors.notFound("environment variable was not found")
        ..
        if code != 0:
            throw errors.native(code, "GetEnvironmentVariableW failed")
        ..
        ret try utf16.toUtf8(ctx.alloc, slices.fromPtr(slices.toPtr(local), 0))
    ..
    if written < 256:
        ret try utf16.toUtf8(ctx.alloc, slices.fromPtr(slices.toPtr(local), written))
    ..
    buffer := try temporary.allocT[u16](written)
    needed := written
    written = ext_GetEnvironmentVariableW(cast.reinterpret[u16](slices.toPtr(wide)), buffer, needed)
    if written == 0:
        code := ext_GetLastError()
        temporary.free(buffer)
        throw errors.native(code, "GetEnvironmentVariableW failed")
    elif written >= needed:
        temporary.free(buffer)
        throw errors.failure("environment variable changed while it was read")
    ..
    result str, conversionError error = utf16.toUtf8(ctx.alloc, slices.fromPtr(buffer, written))
    temporary.free(buffer)
    if conversionError.nok():
        throw conversionError
    ..
    ret move result
..

pub has(name str) bool:
    wide u16[], e error = name16(name)
    if e.nok(): ret false ..
    defer heap.allocator().free(slices.toPtr(wide))
    needed := ext_GetEnvironmentVariableW(cast.reinterpret[u16](slices.toPtr(wide)), none, 0)
    ret needed != 0 || ext_GetLastError() != 203
..

pub set(name str, value str) !void:
    n := try name16(name)
    defer heap.allocator().free(slices.toPtr(n))
    v := try utf8.utf8To16NT(value)
    defer heap.allocator().free(slices.toPtr(v))
    if ext_SetEnvironmentVariableW(cast.reinterpret[u16](slices.toPtr(n)), cast.reinterpret[u16](slices.toPtr(v))) == 0:
        throw errors.native(ext_GetLastError(), "SetEnvironmentVariableW failed")
    ..
..

pub unset(name str) !void:
    n := try name16(name)
    defer heap.allocator().free(slices.toPtr(n))
    if ext_SetEnvironmentVariableW(cast.reinterpret[u16](slices.toPtr(n)), none) == 0:
        throw errors.native(ext_GetLastError(), "SetEnvironmentVariableW failed")
    ..
..

pub list() !$list.List[str]:
    a := ctx.alloc
    block := ext_GetEnvironmentStringsW()
    if block == none: throw errors.native(ext_GetLastError(), "GetEnvironmentStringsW failed") ..
    entries := try list.new[str](a, fn(value $str) void:
        value.free()
    ..)
    onerror entries.free()
    # SAFETY: GetEnvironmentStringsW returns a double-NUL-terminated block;
    # each inner scan stops at an entry terminator and the outer scan stops at
    # the final empty entry.
    unsafe:
        offset u64 = 0
        loop block[offset] != 0:
            count u64 = 0
            loop block[offset + count] != 0: count = count + 1 ..
            value str, conversionError error = utf16.toUtf8(a, slices.fromPtr(addrof block[offset], count))
            if conversionError.nok():
                ext_FreeEnvironmentStringsW(block)
                throw conversionError
            ..
            try entries.pushRight(move value)
            offset = offset + count + 1
        ..
    ..
    if ext_FreeEnvironmentStringsW(block) == 0:
        throw errors.native(ext_GetLastError(), "FreeEnvironmentStringsW failed")
    ..
    ret move entries
..
