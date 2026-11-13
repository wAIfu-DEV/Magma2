mod threadsafe_writer
# Type-erased byte output with complete-write and primitive formatting helpers.

use "std:strings" as strings
use "std:slices"  as slices
use "std:cast"    as cast
use "std:errors"  as errors

pub use "std:threadsafe/writer" threadsafe

# Writer interface for emitting bytes and formatted values.
# @complexity O(1) wrapper calls; underlying writer decides cost.
# Type-erased byte sink. The implementation is borrowed and must remain alive
# and unmoved while this interface is used.
pub proto Writer(
    writeRaw(bytes str) !u64
)

# Statically stored byte sink used by the standard output globals.
pub ConstWriter impl Writer(
    impl ptr,
    fn_write fn(ptr, str) !u64,
)

# Attempts one write and returns the number of bytes accepted.
# @warning A successful call may write fewer bytes than requested.
# @complexity O(N), determined by the underlying sink
# @example
#   written := try output.writeRaw("data")
ConstWriter.writeRaw(bytes str) !u64:
    ret try this.fn_write(this.impl, bytes)
..

constWriterWriteRemaining(cw ConstWriter*, bytes str, firstWritten u64) !u64:
    total u64 = firstWritten
    bound u64 = bytes.countBytes()
    base ptr
    # SAFETY: byte-offset traversal remains within bytes.countBytes().
    unsafe:
        base = strings.toPtr(bytes)
    ..
    loop total < bound:
        remaining u64 = bound - total
        next ptr = cast.utop(cast.ptou(base) + total)
        written u64 = try cw.writeRaw(strings.fromPtrNoCopy(next, remaining))
        if written > remaining:
            throw errors.failure("writer returned more bytes than requested")
        ..
        if written == 0:
            throw errors.failure("writer made no progress")
        ..
        total = total + written
    ..
    ret total
..

# Repeats writes until every byte is accepted or the sink fails to progress.
# @complexity O(N) plus underlying call overhead
# @example
#   try output.write("complete payload")
ConstWriter.write(bytes str) !u64:
    firstWritten u64 = try this.writeRaw(bytes)
    if firstWritten > bytes.countBytes():
        throw errors.failure("writer returned more bytes than requested")
    ..
    if firstWritten == bytes.countBytes():
        ret firstWritten
    ..
    ret try constWriterWriteRemaining(this, bytes, firstWritten)
..

# Writes all bytes followed by a line-feed byte.
# @complexity O(N)
# @example
#   try output.writeLn("record")
ConstWriter.writeLn(bytes str) !u64:
    written u64 = try this.write(bytes)
    written = written + try this.write("\n")
    ret written
..

# Converts to the mutable Writer interface without changing the implementation.
# @ownership The returned interface borrows the same implementation.
# @complexity O(1)
# @example
#   writer := output.toWriter()
ConstWriter.toWriter() Writer:
    ret this.protoBorrow()
..

# Writes the complete byte string or returns an error if the adapter makes no
# progress or reports an invalid count.
# @complexity O(N) plus underlying call overhead
# @example
#   try output.write("complete payload")
Writer.write(bytes str) !u64:
    firstWritten u64 = try this.writeRaw(bytes)

    if firstWritten > bytes.countBytes():
        throw errors.failure("writer returned more bytes than requested")
    ..

    # Happy path, mean and lean
    if firstWritten == bytes.countBytes():
        ret firstWritten
    ..

    total u64 = firstWritten
    bound u64 = bytes.countBytes()
    base ptr
    # SAFETY: byte-offset traversal remains within bytes.countBytes().
    unsafe:
        base = strings.toPtr(bytes)
    ..

    loop total < bound:
        remaining u64 = bound - total
        next ptr = cast.utop(cast.ptou(base) + total)
        written u64 = try this.writeRaw(strings.fromPtrNoCopy(next, remaining))
        if written > remaining:
            throw errors.failure("writer returned more bytes than requested")
        ..
        if written == 0:
            throw errors.failure("writer made no progress")
        ..
        total = total + written
    ..
    ret total
..

# Writes the provided bytes followed by a newline.
# @complexity O(N) for byte count.
# @param bytes string to write
# @returns number of bytes written
# @example
#   try output.writeLn("record")
Writer.writeLn(bytes str) !u64:
    written u64 = try this.write(bytes)
    written = written + try this.write("\n")
    ret written
..

# Writes "true" or "false" based on the boolean value.
# @complexity O(1).
# @param b boolean value
# @returns number of bytes written
# @example
#   try output.writeBool(true)
Writer.writeBool(b bool) !u64:
    if b == true:
        ret try this.write("true")
    else:
        ret try this.write("false")
    ..
..

# Converts a digit 0-9 to its ASCII character.
# @complexity O(1).
digitToChar(i u16) u8:
    if i > 9:
        ret 0
    ..
    digits str = "0123456789"
    ret strings.byteAt(digits, i)
..

# Writes a signed 64-bit integer in decimal form.
# @complexity O(1) bounded by integer width.
# @param num integer value
# @returns number of bytes written
# @example
#   try output.writeInt64(-42)
Writer.writeInt64(num i64) !u64:
    buf := [20]u8
    n u64 = cast.itou(num)
    idx u64 = 20
    isNeg bool = false

    if n == 0:
        ret try this.write("0")
    ..

    if num < 0:
        isNeg = true
        # -(num + 1) is representable even for INT64_MIN.
        n = cast.itou(0 - (num + 1)) + 1
    ..

    loop n != 0:
        idx = idx - 1
        d u16 = cast.u64to16(n % 10)
        bounded idx < buf.count():
            buf[idx] = digitToChar(d)
        ..
        n = n / 10
    ..

    if isNeg:
        idx = idx - 1
        bounded idx < buf.count():
            buf[idx] = strings.byteAt("-", 0)
        ..
    ..

    len u64 = 20 - idx
    bufPtr ptr = slices.toPtr(buf)
    writePtr ptr = cast.utop(cast.ptou(bufPtr) + idx)
    toWrite str = strings.fromPtrNoCopy(writePtr, len)

    ret try this.write(toWrite)
..

# Writes an unsigned 64-bit integer in decimal form.
# @complexity O(1) bounded by integer width.
# @param num integer value
# @returns number of bytes written
# @example
#   try output.writeUint64(42)
Writer.writeUint64(num u64) !u64:
    buf := [20]u8
    n u64 = num
    idx u64 = 20

    if n == 0:
        ret try this.write("0")
    ..

    loop n != 0:
        idx = idx - 1
        d u16 = cast.u64to16(n % 10)
        bounded idx < buf.count():
            buf[idx] = digitToChar(d)
        ..
        n = n / 10
    ..

    len u64 = 20 - idx
    bufPtr ptr = slices.toPtr(buf)
    writePtr ptr = cast.utop(cast.ptou(bufPtr) + idx)
    toWrite str = strings.fromPtrNoCopy(writePtr, len)

    ret try this.write(toWrite)
..


# Writes a floating point value with the provided precision.
# @complexity O(P) for precision digits.
# @param flt floating point value
# @param precision digits after decimal point
# @returns number of bytes written
# @warning Precision is capped at 42 digits; large finite values must fit u64's integer range.
# @example
#   try output.writeFloat64(3.14159, 2)
Writer.writeFloat64(flt f64, precision u64) !u64:
    # bitcast and read bits as u64

    bits u64
    unsafe:
        addrAsU64 u64* = addrof flt
        bits = *addrAsU64
    ..

    EXP_MASK  u64 = 0x7FF0000000000000
    FRAC_MASK u64 = 0x000FFFFFFFFFFFFF
    SIGN_MASK u64 = 0x8000000000000000

    exp  u64 = bits & EXP_MASK
    frac u64 = bits & FRAC_MASK
    sign bool = (bits & SIGN_MASK) != 0

    # is Nan
    if (exp == EXP_MASK) && (frac != 0):
        ret try this.write("nan")
    ..

    # is infinitte
    if (exp == EXP_MASK) && (frac == 0):
        if sign:
            ret try this.write("-inf")
        else:
            ret try this.write("inf")
        ..
    ..

    # cap precision to keep buffer bounded
    if precision > 42:
        precision = 42
    ..

    buf := [64]u8
    idx u64 = 64
    isNeg bool = false
    fltCpy f64 = flt

    if fltCpy < 0.0:
        isNeg = true
        fltCpy = 0.0 - fltCpy
    ..

    intPart u64 = cast.ftou(fltCpy)
    fracPart f64 = fltCpy - cast.utof(intPart)

    scale f64 = 1.0
    for i u64 = 0 to precision:
        scale = scale * 10.0
    ..

    fracInt u64 = 0
    if precision > 0:
        fracInt = cast.ftou(fracPart * scale + 0.5)
    ..

    if (precision > 0) && (cast.utof(fracInt) >= scale):
        fracInt = fracInt - cast.ftou(scale)
        intPart = intPart + 1
    ..

    if precision > 0:
        for i u64 = 0 to precision:
            idx = idx - 1
            d u64 = fracInt % 10
            bounded idx < buf.count():
                buf[idx] = digitToChar(cast.u64to16(d))
            ..
            fracInt = fracInt / 10
        ..

        idx = idx - 1
        bounded idx < buf.count():
            buf[idx] = strings.byteAt(".", 0)
        ..
    ..

    if intPart == 0:
        idx = idx - 1
        bounded idx < buf.count():
            buf[idx] = strings.byteAt("0", 0)
        ..
    else:
        n u64 = intPart
        loop n != 0:
            idx = idx - 1
            d u64 = n % 10
            bounded idx < buf.count():
                buf[idx] = digitToChar(cast.u64to16(d))
            ..
            n = n / 10
        ..
    ..

    if isNeg:
        idx = idx - 1
        bounded idx < buf.count():
            buf[idx] = strings.byteAt("-", 0)
        ..
    ..

    len u64 = 64 - idx
    bufPtr ptr = slices.toPtr(buf)
    writePtr ptr = cast.utop(cast.ptou(bufPtr) + idx)
    toWrite str = strings.fromPtrNoCopy(writePtr, len)

    ret try this.write(toWrite)
..
