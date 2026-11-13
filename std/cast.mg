mod cast
# Explicit pointer, integer, and floating-point conversions.
# @warning Narrowing conversions discard bits when the value does not fit.

use "std:llvm" as ll

# Reinterprets an untyped pointer as a pointer to T without changing its address.
# @complexity O(1)
# @safety x must be correctly aligned and reference a valid T before dereferencing.
# @example
#   typed := cast.reinterpret[Header](raw)
pub reinterpret[T](x ptr) T*:
    ret ll.reinterpret[T](x)
..

# Casts a pointer to u64.
# @complexity O(1).
# @example
#   address := cast.ptou(pointer)
pub noctx ptou(x ptr) u64:
    ret ll.ptrToInt(x)
..

# Casts a u64 to pointer.
# @complexity O(1).
# @safety The integer must represent a valid pointer before dereferencing.
# @example
#   pointer := cast.utop(address)
pub utop(x u64) ptr:
    ret ll.intToPtr(x)
..

# Casts i64 to u64.
# @complexity O(1).
# @example
#   bits := cast.itou(value)
pub itou(x i64) u64:
    ret ll.signedToUnsignedBits(x)
..

# Casts u64 to i64.
# @complexity O(1).
# @example
#   signed := cast.utoi(bits)
pub utoi(x u64) i64:
    ret ll.unsignedToSignedBits(x)
..

# Zero-extends u64 to u128.
# @complexity O(1).
# @example
#   wide := cast.u64to128(value)
pub u64to128(x u64) u128:
    ret ll.zeroExtendU64ToU128(x)
..

# Truncates u128 to u64.
# @warning higher bits are discarded on overflow.
# @complexity O(1).
# @example
#   narrow := cast.u128to64(wide)
pub u128to64(x u128) u64:
    ret ll.truncateU128ToU64(x)
..

# Sign-extends i64 to i128.
# @complexity O(1).
# @example
#   wide := cast.i64to128(value)
pub i64to128(x i64) i128:
    ret ll.signExtendI64ToI128(x)
..

# Truncates i128 to i64.
# @warning higher bits are discarded on overflow.
# @complexity O(1).
# @example
#   narrow := cast.i128to64(wide)
pub i128to64(x i128) i64:
    ret ll.truncateI128ToI64(x)
..

# Converts signed i64 to f64.
# @complexity O(1).
# @warning Large integers may be rounded because f64 cannot represent every i64 exactly.
# @example
#   decimal := cast.itof(value)
pub itof(x i64) f64:
    ret ll.signedToF64(x)
..

# Converts unsigned u64 to f64.
# @complexity O(1).
# @warning Large integers may be rounded because f64 cannot represent every u64 exactly.
# @example
#   decimal := cast.utof(value)
pub utof(x u64) f64:
    ret ll.unsignedToF64(x)
..

# Converts f64 to signed i64.
# @complexity O(1).
# @warning Fractional values are truncated and out-of-range conversion is target-dependent.
# @example
#   integer := cast.ftoi(value)
pub ftoi(x f64) i64:
    ret ll.f64ToSigned(x)
..

# Converts f64 to unsigned u64.
# @complexity O(1).
# @warning Fractional values are truncated and negative or out-of-range conversion is target-dependent.
# @example
#   integer := cast.ftou(value)
pub ftou(x f64) u64:
    ret ll.f64ToUnsigned(x)
..

# Sign-extends i32 to i64.
# @complexity O(1).
# @example
#   wide := cast.i32to64(value)
pub i32to64(x i32) i64:
    ret ll.signExtendI32ToI64(x)
..

# Sign-extends i16 to i64.
# @complexity O(1).
# @example
#   wide := cast.i16to64(value)
pub i16to64(x i16) i64:
    ret ll.signExtendI16ToI64(x)
..

# Sign-extends i8 to i64.
# @complexity O(1).
# @example
#   wide := cast.i8to64(value)
pub i8to64(x i8) i64:
    ret ll.signExtendI8ToI64(x)
..

# Zero-extends u32 to u64.
# @complexity O(1).
# @example
#   wide := cast.u32to64(value)
pub noctx u32to64(x u32) u64:
    ret ll.zeroExtendU32ToU64(x)
..

# Reinterprets a u32 value as the same-width signed integer. Values above
# INT32_MAX become negative, matching C's 32-bit two's-complement ABI.
# @complexity O(1).
pub u32toi32(x u32) i32:
    ret ll.unsigned32ToSignedBits(x)
..

# Zero-extends u16 to u64.
# @complexity O(1).
# @example
#   wide := cast.u16to64(value)
pub noctx u16to64(x u16) u64:
    ret ll.zeroExtendU16ToU64(x)
..

# Zero-extends u8 to u64.
# @complexity O(1).
# @example
#   wide := cast.u8to64(value)
pub u8to64(x u8) u64:
    ret ll.zeroExtendU8ToU64(x)
..

# Truncates i64 to i32.
# @warning higher bits are discarded on overflow.
# @complexity O(1).
# @example
#   narrow := cast.i64to32(value)
pub i64to32(x i64) i32:
    ret ll.truncateI64ToI32(x)
..

# Truncates i64 to i16.
# @warning higher bits are discarded on overflow.
# @complexity O(1).
# @example
#   narrow := cast.i64to16(value)
pub i64to16(x i64) i16:
    ret ll.truncateI64ToI16(x)
..

# Truncates i64 to i8.
# @warning higher bits are discarded on overflow.
# @complexity O(1).
# @example
#   narrow := cast.i64to8(value)
pub i64to8(x i64) i8:
    ret ll.truncateI64ToI8(x)
..

# Truncates u64 to u32.
# @warning higher bits are discarded on overflow.
# @complexity O(1).
# @example
#   narrow := cast.u64to32(value)
pub u64to32(x u64) u32:
    ret ll.truncateU64ToU32(x)
..

# Truncates u64 to u16.
# @warning higher bits are discarded on overflow.
# @complexity O(1).
# @example
#   narrow := cast.u64to16(value)
pub u64to16(x u64) u16:
    ret ll.truncateU64ToU16(x)
..

# Truncates u64 to u8.
# @warning higher bits are discarded on overflow.
# @complexity O(1).
# @example
#   narrow := cast.u64to8(value)
pub u64to8(x u64) u8:
    ret ll.truncateU64ToU8(x)
..
