mod checked
# Checked integer arithmetic, conversions, sizes, and alignment.

use "std:cast" as cast
use "std:errors" as errors
use "std:llvm" as ll

maxU() u64:
    ret 0 - 1
..

maxI() i64:
    ret cast.utoi(maxU() >> 1)
..

minI() i64:
    ret 0 - maxI() - 1
..

maxU128() u128:
    ret 0 - 1
..

maxI128() i128:
    ret 170141183460469231731687303715884105727
..

minI128() i128:
    ret 0 - maxI128() - 1
..

u128ToI128Bits(value u128) i128:
    ret ll.unsigned128ToSignedBits(value)
..

i128ToU128Bits(value i128) u128:
    ret ll.signed128ToUnsignedBits(value)
..

# Checked unsigned 64-bit arithmetic.
pub uAdd(a u64, b u64) !u64:
    result u64 = a + b
    if result < a:
        throw errors.wouldOverflow("unsigned addition overflow")
    ..
    ret result
..

pub uSub(a u64, b u64) !u64:
    if a < b:
        throw errors.wouldOverflow("unsigned subtraction underflow")
    ..
    ret a - b
..

pub uMul(a u64, b u64) !u64:
    if b != 0 && a > maxU() / b:
        throw errors.wouldOverflow("unsigned multiplication overflow")
    ..
    ret a * b
..

pub uDiv(a u64, b u64) !u64:
    if b == 0:
        throw errors.invalidArgument("division by zero")
    ..
    ret a / b
..

pub uShl(value u64, amount u64) !u64:
    if amount >= 64:
        throw errors.invalidArgument("shift count must be below 64")
    ..
    if amount != 0 && value > maxU() >> amount:
        throw errors.wouldOverflow("unsigned left shift overflow")
    ..
    ret value << amount
..

pub uPow(base u64, exponent u64) !u64:
    result u64 = 1
    factor u64 = base
    remaining u64 = exponent
    loop remaining != 0:
        if (remaining & 1) != 0:
            result = try uMul(result, factor)
        ..
        remaining = remaining >> 1
        if remaining != 0:
            factor = try uMul(factor, factor)
        ..
    ..
    ret result
..

# Checked signed 64-bit arithmetic.
pub iAdd(a i64, b i64) !i64:
    if (b > 0 && a > maxI() - b) || (b < 0 && a < minI() - b):
        throw errors.wouldOverflow("signed addition overflow")
    ..
    ret a + b
..

pub iSub(a i64, b i64) !i64:
    if (b > 0 && a < minI() + b) || (b < 0 && a > maxI() + b):
        throw errors.wouldOverflow("signed subtraction overflow")
    ..
    ret a - b
..

pub iMul(a i64, b i64) !i64:
    if a == 0 || b == 0:
        ret 0
    ..
    if (a == -1 && b == minI()) || (b == -1 && a == minI()):
        throw errors.wouldOverflow("signed multiplication overflow")
    ..
    if a > 0:
        if (b > 0 && a > maxI() / b) || (b < 0 && b < minI() / a):
            throw errors.wouldOverflow("signed multiplication overflow")
        ..
    else:
        if (b > 0 && a < minI() / b) || (b < 0 && a < maxI() / b):
            throw errors.wouldOverflow("signed multiplication overflow")
        ..
    ..
    ret a * b
..

pub iDiv(a i64, b i64) !i64:
    if b == 0:
        throw errors.invalidArgument("division by zero")
    ..
    if a == minI() && b == -1:
        throw errors.wouldOverflow("signed division overflow")
    ..
    ret a / b
..

pub iNeg(value i64) !i64:
    if value == minI():
        throw errors.wouldOverflow("signed negation overflow")
    ..
    ret 0 - value
..

pub iShl(value i64, amount u64) !i64:
    if amount >= 64:
        throw errors.invalidArgument("shift count must be below 64")
    ..
    result i64 = value
    for i u64 = 0 to amount:
        result = try iAdd(result, result)
    ..
    ret result
..

pub iPow(base i64, exponent u64) !i64:
    result i64 = 1
    factor i64 = base
    remaining u64 = exponent
    loop remaining != 0:
        if (remaining & 1) != 0:
            result = try iMul(result, factor)
        ..
        remaining = remaining >> 1
        if remaining != 0:
            factor = try iMul(factor, factor)
        ..
    ..
    ret result
..

# Checked unsigned 128-bit arithmetic.
pub u128Add(a u128, b u128) !u128:
    result u128 = a + b
    if result < a:
        throw errors.wouldOverflow("unsigned 128-bit addition overflow")
    ..
    ret result
..

pub u128Sub(a u128, b u128) !u128:
    if a < b:
        throw errors.wouldOverflow("unsigned 128-bit subtraction underflow")
    ..
    ret a - b
..

pub u128Mul(a u128, b u128) !u128:
    if b != 0 && a > maxU128() / b:
        throw errors.wouldOverflow("unsigned 128-bit multiplication overflow")
    ..
    ret a * b
..

pub u128Div(a u128, b u128) !u128:
    if b == 0:
        throw errors.invalidArgument("division by zero")
    ..
    ret a / b
..

pub u128Shl(value u128, amount u64) !u128:
    if amount >= 128:
        throw errors.invalidArgument("shift count must be below 128")
    ..
    if amount != 0 && value > maxU128() >> amount:
        throw errors.wouldOverflow("unsigned 128-bit left shift overflow")
    ..
    ret value << amount
..

pub u128Pow(base u128, exponent u64) !u128:
    result u128 = 1
    factor u128 = base
    remaining u64 = exponent
    loop remaining != 0:
        if (remaining & 1) != 0:
            result = try u128Mul(result, factor)
        ..
        remaining = remaining >> 1
        if remaining != 0:
            factor = try u128Mul(factor, factor)
        ..
    ..
    ret result
..

# Checked signed 128-bit arithmetic.
pub i128Add(a i128, b i128) !i128:
    if (b > 0 && a > maxI128() - b) || (b < 0 && a < minI128() - b):
        throw errors.wouldOverflow("signed 128-bit addition overflow")
    ..
    ret a + b
..

pub i128Sub(a i128, b i128) !i128:
    if (b > 0 && a < minI128() + b) || (b < 0 && a > maxI128() + b):
        throw errors.wouldOverflow("signed 128-bit subtraction overflow")
    ..
    ret a - b
..

pub i128Mul(a i128, b i128) !i128:
    if a == 0 || b == 0:
        ret 0
    ..
    if (a == -1 && b == minI128()) || (b == -1 && a == minI128()):
        throw errors.wouldOverflow("signed 128-bit multiplication overflow")
    ..
    if a > 0:
        if (b > 0 && a > maxI128() / b) || (b < 0 && b < minI128() / a):
            throw errors.wouldOverflow("signed 128-bit multiplication overflow")
        ..
    else:
        if (b > 0 && a < minI128() / b) || (b < 0 && a < maxI128() / b):
            throw errors.wouldOverflow("signed 128-bit multiplication overflow")
        ..
    ..
    ret a * b
..

pub i128Div(a i128, b i128) !i128:
    if b == 0:
        throw errors.invalidArgument("division by zero")
    ..
    if a == minI128() && b == -1:
        throw errors.wouldOverflow("signed 128-bit division overflow")
    ..
    ret a / b
..

pub i128Neg(value i128) !i128:
    if value == minI128():
        throw errors.wouldOverflow("signed 128-bit negation overflow")
    ..
    ret 0 - value
..

pub i128Shl(value i128, amount u64) !i128:
    if amount >= 128:
        throw errors.invalidArgument("shift count must be below 128")
    ..
    result i128 = value
    for i u64 = 0 to amount:
        result = try i128Add(result, result)
    ..
    ret result
..

pub i128Pow(base i128, exponent u64) !i128:
    result i128 = 1
    factor i128 = base
    remaining u64 = exponent
    loop remaining != 0:
        if (remaining & 1) != 0:
            result = try i128Mul(result, factor)
        ..
        remaining = remaining >> 1
        if remaining != 0:
            factor = try i128Mul(factor, factor)
        ..
    ..
    ret result
..

# Checked narrowing and signedness conversions. The unsuffixed u and i names
# denote Magma's default u64 and i64 integer widths.
pub uToU8(value u64) !u8:
    if value > 255:
        throw errors.wouldOverflow("u64 value does not fit u8")
    ..
    ret cast.u64to8(value)
..

pub uToU16(value u64) !u16:
    if value > 65535:
        throw errors.wouldOverflow("u64 value does not fit u16")
    ..
    ret cast.u64to16(value)
..

pub uToU32(value u64) !u32:
    if value > 4294967295:
        throw errors.wouldOverflow("u64 value does not fit u32")
    ..
    ret cast.u64to32(value)
..

pub iToI8(value i64) !i8:
    if value < -128 || value > 127:
        throw errors.wouldOverflow("i64 value does not fit i8")
    ..
    ret cast.i64to8(value)
..

pub iToI16(value i64) !i16:
    if value < -32768 || value > 32767:
        throw errors.wouldOverflow("i64 value does not fit i16")
    ..
    ret cast.i64to16(value)
..

pub iToI32(value i64) !i32:
    if value < -2147483648 || value > 2147483647:
        throw errors.wouldOverflow("i64 value does not fit i32")
    ..
    ret cast.i64to32(value)
..

pub uToI(value u64) !i64:
    if value > cast.itou(maxI()):
        throw errors.wouldOverflow("u64 value does not fit i64")
    ..
    ret cast.utoi(value)
..

pub iToU(value i64) !u64:
    if value < 0:
        throw errors.wouldOverflow("negative i64 value does not fit u64")
    ..
    ret cast.itou(value)
..

pub u128ToU(value u128) !u64:
    if value > cast.u64to128(maxU()):
        throw errors.wouldOverflow("u128 value does not fit u64")
    ..
    ret cast.u128to64(value)
..

pub i128ToI(value i128) !i64:
    if value < cast.i64to128(minI()) || value > cast.i64to128(maxI()):
        throw errors.wouldOverflow("i128 value does not fit i64")
    ..
    ret cast.i128to64(value)
..

pub u128ToI128(value u128) !i128:
    if value > i128ToU128Bits(maxI128()):
        throw errors.wouldOverflow("u128 value does not fit i128")
    ..
    ret u128ToI128Bits(value)
..

pub i128ToU128(value i128) !u128:
    if value < 0:
        throw errors.wouldOverflow("negative i128 value does not fit u128")
    ..
    ret i128ToU128Bits(value)
..

# Checked allocation-size helpers.
pub byteCount[T](count u64) !u64:
    ret try uMul(count, sizeof T)
..

pub addByteCount(base u64, count u64, elementSize u64) !u64:
    ret try uAdd(base, try uMul(count, elementSize))
..

pub elementCount(byteCountValue u64, elementSize u64) !u64:
    if elementSize == 0:
        throw errors.invalidArgument("element size must be nonzero")
    ..
    if byteCountValue % elementSize != 0:
        throw errors.invalidArgument("byte count is not a whole number of elements")
    ..
    ret byteCountValue / elementSize
..

powerOfTwo(value u64) bool:
    ret value != 0 && (value & (value - 1)) == 0
..

pub alignUp(value u64, alignment u64) !u64:
    if powerOfTwo(alignment) == false:
        throw errors.invalidArgument("alignment must be a nonzero power of two")
    ..
    ret (try uAdd(value, alignment - 1)) & (0 - alignment)
..

pub alignDown(value u64, alignment u64) !u64:
    if powerOfTwo(alignment) == false:
        throw errors.invalidArgument("alignment must be a nonzero power of two")
    ..
    ret value & (0 - alignment)
..

pub isAligned(value u64, alignment u64) bool:
    if powerOfTwo(alignment) == false:
        ret false
    ..
    ret (value & (alignment - 1)) == 0
..
