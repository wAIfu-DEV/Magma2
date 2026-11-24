mod compiler_known

use "std:strings" strgs
use "shared/global" gl

# Resolves compiler-owned type names to the primitive types for the current
# host ABI. Keep this mapping outside the checker so every type position that
# accepts @compiler_known_type uses the same resolution path.
pub resolve(name str) str:
    isWindows := strgs.byteAt(gl.cwd, 1) == 58
    if name == "c.char" || name == "c.signed_char": ret "i8" ..
    if name == "c.unsigned_char": ret "u8" ..
    if name == "c.short": ret "i16" ..
    if name == "c.unsigned_short": ret "u16" ..
    if name == "c.int": ret "i32" ..
    if name == "c.unsigned_int": ret "u32" ..
    if name == "c.long":
        if isWindows: ret "i32" ..
        ret "i64"
    ..
    if name == "c.unsigned_long":
        if isWindows: ret "u32" ..
        ret "u64"
    ..
    if name == "c.long_long": ret "i64" ..
    if name == "c.unsigned_long_long": ret "u64" ..
    if name == "c.size_t" || name == "c.uintptr_t": ret "u64" ..
    if name == "c.ptrdiff_t" || name == "c.intptr_t" || name == "c.time_t": ret "i64" ..
    if name == "c.wchar_t":
        if isWindows: ret "u16" ..
        ret "i32"
    ..
    ret ""
..
