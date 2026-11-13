mod fmt
# Deferred, typed string formatting for output streams and owned strings.

use "std:allocator" as alc
use "std:errors" as errors
use "std:io" as io
use "std:memory" as memory
use "std:strings" as strings
use "std:writer" as writer

const INITIAL_CAPACITY u64 = 8
union Part(
    String(value str)
    Uint(value u64)
    Int(value i64)
    Bool(value bool)
    Float(value f64, precision u64)
)

stringPart(value str) Part:
    ret Part.String(value=value)
..

uintPart(value u64) Part:
    ret Part.Uint(value=value)
..

intPart(value i64) Part:
    ret Part.Int(value=value)
..

boolPart(value bool) Part:
    ret Part.Bool(value=value)
..

floatPart(value f64, precision u64) Part:
    ret Part.Float(value=value, precision=precision)
..

# A short-lived, deferred sequence of typed formatting operations. Strings are
# borrowed and must remain valid until the Format is consumed or freed.
pub Format(
    allocator alc.Allocator
    parts Part*
    count u64
    capacity u64
    failure error
)

failed(f Format*) bool:
    ret f.failure.nok()
..

remember(f Format*, failure error) void:
    if f.failure.ok():
        f.failure = failure
    ..
..

ensureCapacity(f Format*) bool:
    if failed(f) || f.count < f.capacity:
        ret f.failure.ok()
    ..

    maxU64 u64 = 0 - 1
    if f.capacity > maxU64 / 2:
        remember(f, errors.wouldOverflow("format part capacity overflow"))
        ret false
    ..

    newCapacity := f.capacity * 2
    resized Part*, resizeErr error = f.allocator.reallocT[Part](f.parts, newCapacity)
    if resizeErr.nok():
        remember(f, resizeErr)
        ret false
    ..
    f.parts = resized
    f.capacity = newCapacity
    ret true
..

append(f Format*, part Part) void:
    if ensureCapacity(f) == false:
        ret
    ..
    # SAFETY: ensureCapacity guarantees an initialized allocation with a free
    # slot at count.
    unsafe:
        f.parts[f.count] = part
    ..
    f.count = f.count + 1
..

# Starts a format with one borrowed string and room for eight parts. Allocation
# failure is retained and reported by the terminal operation.
# @complexity O(1), excluding allocator cost
# @ownership initial is borrowed until the Format is consumed or freed.
# @example
#   format := fmt.str(a, "count: ").uint(42)
pub str(a alc.Allocator, initial str) $Format:
    parts Part*, allocErr error = a.allocT[Part](INITIAL_CAPACITY)
    result := Format(
        allocator=a,
        parts=parts,
        count=0,
        capacity=INITIAL_CAPACITY,
        failure=allocErr,
    )
    append(addrof result, stringPart(initial))
    ret move result
..

pub new(a alc.Allocator) $Format:
    parts Part*, allocErr error = a.allocT[Part](INITIAL_CAPACITY)
    result := Format(
        allocator=a,
        parts=parts,
        count=0,
        capacity=INITIAL_CAPACITY,
        failure=allocErr,
    )
    ret move result
..

# Appends a borrowed string part.
# @complexity Amortized O(1)
# @ownership value must remain valid until the Format is consumed or freed.
Format.str(value str) $Format:
    append(this, stringPart(value))
    ret *this
..

# Appends an unsigned decimal integer.
# @complexity Amortized O(1)
Format.uint(value u64) $Format:
    append(this, uintPart(value))
    ret *this
..

# Appends a signed decimal integer.
# @complexity Amortized O(1)
Format.int(value i64) $Format:
    append(this, intPart(value))
    ret *this
..

# Appends `true` or `false`.
# @complexity Amortized O(1)
Format.bool(value bool) $Format:
    append(this, boolPart(value))
    ret *this
..

# Appends a floating-point value with precision digits after the decimal point.
# @complexity Amortized O(1) to append; O(precision) when rendered
Format.float(value f64, precision u64) $Format:
    append(this, floatPart(value, precision))
    ret *this
..

writeParts(f Format*, out writer.Writer) !u64:
    if failed(f):
        throw f.failure
    ..
    if f.count > f.capacity:
        throw errors.failure("invalid format part count")
    ..

    written u64 = 0
    for i u64 = 0 to f.count:
        part Part
        # SAFETY: Format maintains count <= capacity and initializes each part.
        unsafe:
            part = f.parts[i]
        ..
        next u64 = 0
        match part as value:
        case Part.String:
            next = try out.write(value.value)
        case Part.Uint:
            next = try out.writeUint64(value.value)
        case Part.Int:
            next = try out.writeInt64(value.value)
        case Part.Bool:
            next = try out.writeBool(value.value)
        case Part.Float:
            next = try out.writeFloat64(value.value, value.precision)
        else:
            throw errors.invalidType("unknown format part type")
        ..

        maxU64 u64 = 0 - 1
        if next > maxU64 - written:
            throw errors.wouldOverflow("formatted byte count overflow")
        ..
        written = written + next
    ..
    ret written
..

release(f Format*) void:
    if f.parts != none:
        f.allocator.free(f.parts)
        f.parts = none
    ..
    f.count = 0
    f.capacity = 0
..

# Writes the deferred format and consumes it. A construction error is reported
# before any bytes are written.
# @complexity O(P + B), for part count P and rendered byte count B
# @returns total bytes written
# @example
#   written := try format.writeTo(output)
destr Format.writeTo(out writer.Writer) !u64:
    written u64, writeErr error = writeParts(this, out)
    release(this)
    if writeErr.nok():
        throw writeErr
    ..
    ret written
..

# Writes the deferred format to standard output and consumes it.
# @complexity O(P + B)
# @returns total bytes written
# @example
#   try fmt.str(a, "count: ").uint(42).print()
destr Format.print() !u64:
    out := io.stdoutConst().toWriter()
    written u64, writeErr error = writeParts(this, out)
    release(this)
    if writeErr.nok():
        throw writeErr
    ..
    ret written
..

# Writes and consumes a deferred format on standard output.
# @complexity O(P + B)
# @example
#   try fmt.printf(fmt.str(a, "ready: ").bool(true))
pub printf(format $Format) !void:
    try format.print()
..

CountWriter impl writer.Writer(value u8)

CountWriter.writeRaw(bytes str) !u64:
    ret bytes.countBytes()
..

BufferSink impl writer.Writer(
    out u8*
    offset u64
)

BufferSink.writeRaw(bytes str) !u64:
    count := bytes.countBytes()
    # SAFETY: render allocates enough output for every accepted write.
    unsafe:
        for i u64 = 0 to count:
            this.out[this.offset + i] = strings.byteAt(bytes, i)
        ..
        this.offset = this.offset + count
    ..
    ret count
..

# Renders the deferred format into a newly allocated string and consumes it.
# @complexity O(P + B)
# @ownership Release the returned string with a.
# @example
#   text := try format.toStr(a)
destr Format.toStr(a alc.Allocator) !$str:
    if failed(this):
        constructionErr := this.failure
        release(this)
        throw constructionErr
    ..
    countWriter := CountWriter(value=0)
    counter := countWriter.proto[writer.Writer]()
    total u64, countErr error = writeParts(this, counter)
    if countErr.nok():
        release(this)
        throw countErr
    ..
    result $str, allocErr error = strings.alloc(total)
    if allocErr.nok():
        release(this)
        throw allocErr
    ..
    onerror result.free()

    sink := BufferSink(out=strings.toPtr(result), offset=0)
    out := sink.proto[writer.Writer]()
    ignored u64, writeErr error = writeParts(this, out)
    release(this)
    if writeErr.nok(): throw writeErr ..
    ret move result
..

# Discards a format without rendering it.
# @complexity O(1), excluding allocator cost
# @example
#   format.free()
destr Format.free() void:
    release(this)
..
