mod utf8
# UTF-8 decoding and conversion between UTF-8 and UTF-16 representations.

# TODO: rewrite magic numbers using 0x notation

use "std:errors"    as errors
use "std:strings"   as strings
use "std:slices"    as slices
use "std:cast"      as cast
use "std:allocator" as alc
use "std:unicode"   as unicode
use "std:checked"   as checked

# Iterator over a UTF-8 byte range.
# @complexity O(1) for iterator operations.
pub Utf8Iterator(
    start ptr,
    end   ptr,
)

# A decoded Unicode codepoint and its UTF-8 width in bytes.
# @complexity O(1).
pub Codepoint(value u32, width u8)

# Progress from an incremental decode operation.
pub DecodeResult(consumed u64, written u64, needsInput bool, needsOutput bool)

# Incremental UTF-8 decoder. pending stores at most one packed scalar sequence.
pub Decoder(pending u32, pendingCount u8, pendingWidth u8)

# Creates an empty incremental UTF-8 decoder.
pub newDecoder() Decoder:
    ret Decoder(pending=0, pendingCount=0, pendingWidth=0)
..

sequenceWidth(first u8) u8:
    if (first & 0x80) == 0:
        ret 1
    elif (first & 0xE0) == 0xC0:
        ret 2
    elif (first & 0xF0) == 0xE0:
        ret 3
    elif (first & 0xF8) == 0xF0:
        ret 4
    ..
    ret 0
..

Decoder.appendPending(byte u8) void:
    shift u32 = cast.u64to32(cast.u8to64(this.pendingCount) * 8)
    this.pending = this.pending | (u8to32(byte) << shift)
    this.pendingCount = this.pendingCount + 1
..

Decoder.emitPending(output u32[], written u64*) !void:
    # SAFETY: Decoder.push calls this only after proving written is below the
    # caller-provided output count; pendingCount is limited to four bytes.
    unsafe:
    bytes := [4]u8
    for i u64 = 0 to cast.u8to64(this.pendingCount):
        shift u32 = cast.u64to32(i * 8)
        bytes[i] = u32to8((this.pending >> shift) & 0xFF)
    ..
    view u8[] = slices.fromPtr(slices.toPtr(bytes), cast.u8to64(this.pendingCount))
    cp, e := decode(view)
    this.pending = 0
    this.pendingCount = 0
    this.pendingWidth = 0
    if e.nok():
        throw e
    ..
    output[*written] = cp.value
      *written = *written + 1
    ..
..

# Decodes complete scalars from a chunk into caller-provided u32 storage.
# Incomplete trailing input is retained by the decoder.
pub Decoder.push(input u8[], output u32[]) !DecodeResult:
    consumed u64 = 0
    written u64 = 0
    inputCount := slices.count(input)
    outputCount := slices.count(output)

    loop true:
        if this.pendingCount != 0:
            loop this.pendingCount < this.pendingWidth && consumed < inputCount:
                this.appendPending(input[consumed])
                consumed = consumed + 1
            ..
            if this.pendingCount < this.pendingWidth:
                ret DecodeResult(consumed=consumed, written=written, needsInput=true, needsOutput=false)
            ..
            if written >= outputCount:
                ret DecodeResult(consumed=consumed, written=written, needsInput=false, needsOutput=true)
            ..
            try this.emitPending(output, addrof written)
            continue
        ..

        if consumed >= inputCount:
            ret DecodeResult(consumed=consumed, written=written, needsInput=false, needsOutput=false)
        ..
        if written >= outputCount:
            ret DecodeResult(consumed=consumed, written=written, needsInput=false, needsOutput=true)
        ..
        width := sequenceWidth(input[consumed])
        if width == 0:
            throw errors.failure("invalid UTF-8 leading byte")
        ..
        this.pendingWidth = width
        loop this.pendingCount < width && consumed < inputCount:
            this.appendPending(input[consumed])
            consumed = consumed + 1
        ..
    ..
..

# Verifies that no incomplete scalar remains at end of input.
pub Decoder.finish() !void:
    if this.pendingCount != 0:
        throw errors.failure("incomplete UTF-8 sequence at end of input")
    ..
..

# Converts an 8-bit value to u32.
# @complexity O(1).
u8to32(v u8) u32:
    ret cast.u64to32(cast.u8to64(v))
..

# Converts a u32 to an 8-bit value.
# @complexity O(1).
u32to8(v u32) u8:
    ret cast.u64to8(cast.u32to64(v))
..

# Converts a u16 to u32.
# @complexity O(1).
u16to32(v u16) u32:
    ret cast.u64to32(cast.u16to64(v))
..

# Converts a u32 to u16.
# @complexity O(1).
u32to16(v u32) u16:
    ret cast.u64to16(cast.u32to64(v))
..

# Decodes the next codepoint without advancing the iterator.
# @complexity O(1) for a single codepoint.
decodeOnce(it Utf8Iterator*) !Codepoint:
    if it.start == none || it.end == none:
        throw errors.invalidArgument("Utf8Iterator was not correctly initialized, use utf8.iterator")
    ..
    cp Codepoint = decodeFirst(cast.reinterpret[u8](it.start), cast.reinterpret[u8](it.end))
    if cp.width == 0:
        throw errors.failure("failed to decode utf8 codepoint")
    ..
    ret cp
..

# Creates a UTF-8 iterator over a string.
# @complexity O(1).
# @param s input string
# @returns iterator over UTF-8 bytes in s
# @ownership The iterator borrows s, which must remain alive and unmoved.
# @example
#   it := utf8.iterator(text)
pub iterator(s str) Utf8Iterator:
    p u8* = strings.toPtr(s)
    sLen u64 = s.countBytes()
    ret Utf8Iterator(start=p, end=cast.utop(cast.ptou(p) + sLen))
..

# Returns the next codepoint without advancing.
# @complexity O(1) for a single codepoint.
# @throws failure if the next byte sequence is invalid UTF-8
# @example
#   cp := try it.peek()
Utf8Iterator.peek() !Codepoint:
    ret try decodeOnce(this)
..

# Returns the next codepoint and advances the iterator.
# @complexity O(1) for a single codepoint.
# @throws failure if the next byte sequence is invalid UTF-8
# @example
#   cp := try it.next()
Utf8Iterator.next() !Codepoint:
    cp Codepoint = try this.peek()
    this.start = cast.utop(cast.ptou(this.start) + cast.u8to64(cp.width))
    ret cp
..

# Returns true if there are more bytes to decode.
# @complexity O(1).
# @example
#   while it.hasData():
Utf8Iterator.hasData() bool:
    if this.start == none || this.end == none:
        ret false
    ..
    ret cast.ptou(this.start) < cast.ptou(this.end)
..

# Decodes a single UTF-8 codepoint from start, validating bounds.
# @complexity O(1) for a single codepoint.
# Hottest function for UTF8 decoding, most prone to be optimized in the future
# Keep bloat out of it, no defers or error return as those will increase
# complexity and obfuscate the happy path.
decodeFirst(start u8*, end u8*) Codepoint:
    # SAFETY: start/end delimit one live UTF-8 byte range; width is validated
    # against their difference before continuation-byte indexing.
    unsafe:
    outCp := Codepoint(value=0, width=0)

    if cast.ptou(start) >= cast.ptou(end):
        ret outCp
    ..

    first u8 = *start
    width u8 = 0
    codepoint u32 = 0

    if (first & 128) == 0:
        width = 1
        codepoint = u8to32(first)
    elif (first & 224) == 192:
        width = 2
        codepoint = u8to32(first & 31)
    elif (first & 240) == 224:
        width = 3
        codepoint = u8to32(first & 15)
    elif (first & 248) == 240:
        width = 4
        codepoint = u8to32(first & 7)
    else:
        ret outCp
    ..

    ptdiff u64 = cast.ptou(end) - cast.ptou(start)
    if ptdiff < cast.u8to64(width):
        ret outCp
    ..

    cont u8 = 0
    for i u64 = 1 to cast.u8to64(width):

        cont = start[i]

        if (cont & 192) != 128:
            ret outCp
        ..
        codepoint = (codepoint << 6) | u8to32(cont & 63)
    ..

    # Validate against overlong encodings
    if width == 1:
        # Single byte: must be < 128
        if codepoint >= 128:
            ret outCp
        ..
    elif width == 2:
        # Two bytes: must be in range U+0080 to U+07FF
        if codepoint < 128 || codepoint > 2047:
            ret outCp
        ..
    elif width == 3:
        # Three bytes: must be in range U+0800 to U+FFFF
        if codepoint < 2048 || codepoint > 65535:
            ret outCp
        ..
        # Check for surrogate pairs (U+D800 to U+DFFF)
        if codepoint >= 55296 && codepoint <= 57343:
            ret outCp
        ..
    elif width == 4:
        # Four bytes: must be in range U+10000 to U+10FFFF
        if codepoint < 65536 || codepoint > 1114111:
            ret outCp
        ..
    else:
        ret outCp
    ..

    # If we get here, validation passed
      ret Codepoint(value=codepoint, width=width)
    ..
..

# Decodes the first scalar from a byte slice.
# @throws failure when the input is empty or begins with invalid UTF-8
# @complexity O(1)
pub decode(bytes u8[]) !Codepoint:
    count := slices.count(bytes)
    if count == 0:
        throw errors.failure("cannot decode empty UTF-8 input")
    ..
    start u8* = cast.reinterpret[u8](slices.toPtr(bytes))
    end u8* = cast.reinterpret[u8](cast.utop(cast.ptou(start) + count))
    cp := decodeFirst(start, end)
    if cp.width == 0:
        throw errors.failure("invalid UTF-8 sequence")
    ..
    ret cp
..

# Reports whether a string is entirely valid UTF-8.
# @complexity O(N)
pub validate(s str) bool:
    it := iterator(s)
    loop it.hasData():
        cp, e := it.next()
        if e.nok():
            ret false
        ..
    ..
    ret true
..

# Returns the number of UTF-16 code units needed to encode a UTF-8 string.
# @complexity O(N) for UTF-8 byte count.
utf8to16size(s str) !u64:
    it Utf8Iterator = iterator(s)
    total u64 = 0

    loop it.hasData():
        cp Codepoint = try it.next()
        v u32 = cp.value

        if v <= 65535 && (v < 55296 || v > 57343):
            total = total + 1
        else:
            total = total + 2
        ..
    ..
    ret total
..

# Converts UTF-8 string to UTF-16 code units.
# @complexity O(N) for UTF-8 byte count.
# @param a allocator to use
# @param s input UTF-8 string
# @returns UTF-16 slice
# @throws failure if s contains invalid UTF-8
# @ownership The caller owns the returned storage and must free it with a.
# @example
#   wide := try utf8.utf8To16(a, text)
pub utf8To16(s str) !$u16[]:
    a := ctx.alloc
    # SAFETY: utf8to16size computes the exact code-unit allocation and the
    # validated iterator emits exactly that many units.
    unsafe:
    it Utf8Iterator = iterator(s)

    elemCount u64 = try utf8to16size(s)
    if elemCount == 0:
        ret slices.fromPtr(none, 0)
    ..
    outSize u64 = try checked.byteCount[u16](elemCount)
    outPtr u16* = try a.alloc(outSize)
    onerror a.free(outPtr)

    i u64 = 0
    loop it.hasData():
        cp Codepoint = try it.next()
        v u32 = cp.value

        if v <= 65535 && (v < 55296 || v > 57343):
            outPtr[i] = u32to16(v)
            i = i + 1
        else:
            v = v - 65536
            high u16 = u32to16((v >> 10) + 55296)
            low u16 = u32to16((v & 1023) + 56320)

            outPtr[i] = high
            i = i + 1

            outPtr[i] = low
            i = i + 1
        ..
    ..
      ret slices.fromPtr(outPtr, elemCount)
    ..
..

# Converts UTF-8 string to null-terminated UTF-16 code units.
# @complexity O(N) for UTF-8 byte count.
# @param a allocator to use
# @param s input UTF-8 string
# @returns UTF-16 slice, null-terminated
# Converts UTF-8 to UTF-16 and appends a zero code unit for C APIs.
# @complexity O(N) for UTF-8 byte count
# @throws failure if s contains invalid UTF-8
# @ownership The caller owns the returned storage and must free it with a.
# @example
#   wideC := try utf8.utf8To16NT(a, text)
pub utf8To16NT(s str) !$u16[]:
    a := ctx.alloc
    # SAFETY: allocationCount includes the terminator and utf8to16size exactly
    # bounds all code units emitted by the validated iterator.
    unsafe:
    it Utf8Iterator = iterator(s)

    elemCount u64 = try utf8to16size(s)
    allocationCount := try checked.uAdd(elemCount, 1)
    outSize u64 = try checked.byteCount[u16](allocationCount)
    outPtr u16* = try a.alloc(outSize)
    onerror a.free(outPtr)
    
    outPtr[elemCount] = 0

    i u64 = 0
    loop it.hasData():
        cp Codepoint = try it.next()
        v u32 = cp.value

        if v <= 65535 && (v < 55296 || v > 57343):
            outPtr[i] = u32to16(v)
            i = i + 1
        else:
            v = v - 65536
            high u16 = u32to16((v >> 10) + 55296)
            low u16 = u32to16((v & 1023) + 56320)

            outPtr[i] = high
            i = i + 1

            outPtr[i] = low
            i = i + 1
        ..
    ..
      ret slices.fromPtr(outPtr, elemCount)
    ..
..

# Encodes a single codepoint into UTF-8.
# @complexity O(1).
encodeUtf8(cp u32, out u8*) !u64:
    # SAFETY: callers reserve four writable bytes at out; each scalar branch
    # writes only its returned UTF-8 width.
    unsafe:
    if cp <= 127:
        *out = u32to8(cp)
        ret 1
    elif cp <= 2047:
        *out = u32to8(192 | (cp >> 6))
        out[1] = u32to8(128 | (cp & 63))
        ret 2
    elif cp <= 65535:
        if cp >= 55296 && cp <= 57343:
            throw errors.failure("invalid unicode scalar value")
        ..
        *out = u32to8(224 | (cp >> 12))
        out[1] = u32to8(128 | ((cp >> 6) & 63))
        out[2] = u32to8(128 | (cp & 63))
        ret 3
    elif cp <= 1114111:
        *out = u32to8(240 | (cp >> 18))
        out[1] = u32to8(128 | ((cp >> 12) & 63))
        out[2] = u32to8(128 | ((cp >> 6) & 63))
        out[3] = u32to8(128 | (cp & 63))
        ret 4
    else:
        throw errors.failure("invalid unicode codepoint")
    ..
      ret 0
    ..
..

# Returns the UTF-8 width of a Unicode scalar.
# @throws invalidArgument when cp is not a scalar value
# @complexity O(1)
pub encodedSize(cp u32) !u64:
    if unicode.isScalar(cp) == false:
        throw errors.invalidArgument("invalid Unicode scalar value")
    ..
    ret codepointUtf8Size(cp)
..

# Encodes one Unicode scalar into caller-provided storage.
# @returns number of bytes written
# @throws invalidArgument for an invalid scalar or undersized output
# @complexity O(1)
pub encode(cp u32, output u8[]) !u64:
    needed := try encodedSize(cp)
    if slices.count(output) < needed:
        throw errors.invalidArgument("UTF-8 output buffer is too small")
    ..
    ret try encodeUtf8(cp, cast.reinterpret[u8](slices.toPtr(output)))
..

# Returns the number of UTF-8 bytes needed to encode a UTF-16 slice.
# @complexity O(N) for UTF-16 length.
# @param in input UTF-16 slice
# @returns required UTF-8 byte count
# Returns the UTF-8 byte count required to encode a UTF-16 slice.
# A trailing zero is treated as ordinary U+0000 rather than a terminator.
# @complexity O(N) for UTF-16 code units
# @throws failure for unpaired or malformed surrogates
# @example
#   bytes := try utf8.utf16to8size(wide)
pub utf16to8size(in u16[]) !u64:
    n u64 = slices.count(in)
    totalBytes u64 = 0
    i u64 = 0

    loop i < n:
        w1 u16 = in[i]
        i = i + 1

        cp u32 = 0

        if w1 < 55296 || w1 > 57343:
            cp = u16to32(w1)

            if cp > 1114111:
                throw errors.failure("invalid unicode scalar value")
            ..

            totalBytes = totalBytes + codepointUtf8Size(cp)
            continue
        ..

        if w1 >= 55296 && w1 <= 56319:
            if i >= n:
                throw errors.failure("unterminated utf16 surrogate pair")
            ..

            w2 u16 = in[i]
            i = i + 1

            if w2 < 56320 || w2 > 57343:
                throw errors.failure("invalid utf16 surrogate pair")
            ..

            high u32 = u16to32(w1 - 55296)
            low  u32 = u16to32(w2 - 56320)
            cp = ((high << 10) | low) + cast.u64to32(65536)

            if cp > 1114111:
                throw errors.failure("invalid unicode scalar value")
            ..

            totalBytes = totalBytes + codepointUtf8Size(cp)
            continue
        ..

        throw errors.failure("unexpected low utf16 surrogate")
    ..
    ret totalBytes
..

# Returns UTF-8 byte length for a codepoint.
# @complexity O(1).
codepointUtf8Size(cp u32) u64:
    if cp <= 127:
        ret 1
    elif cp <= 2047:
        ret 2
    elif cp <= 65535:
        ret 3
    elif cp <= 1114111:
        ret 4
    else:
        ret 0
    ..
..

# Encodes one UTF-16 codepoint (or surrogate pair) to UTF-8.
# @complexity O(1) for a single codepoint or surrogate pair.
utf16to8iter(in u16[], out u8*, i u64*, n u64) !u64:
    # SAFETY: callers pass n = count(in), keep *i <= n, and reserve four output
    # bytes; the surrogate lookahead explicitly checks *i < n.
    unsafe:
    w1 u16 = in[*i]
    *i = *i + 1

    if w1 < 55296 || w1 > 57343:
        ret try encodeUtf8(u16to32(w1), out)
    ..

    if w1 <= 56319:
        if *i >= n:
            throw errors.failure("unterminated utf16 surrogate pair")
        ..

        w2 u16 = in[*i]
        *i = *i + 1

        if w2 < 56320 || w2 > 57343:
            throw errors.failure("invalid utf16 surrogate pair")
        ..

        high u32 = u16to32(w1 - 55296)
        low  u32 = u16to32(w2 - 56320)
        cp u32 = ((high << 10) | low) + 65536

        ret try encodeUtf8(cp, out)
    ..

      throw errors.failure("unexpected low utf16 surrogate")
    ..
..

# Converts UTF-16 code units to a UTF-8 string.
# @complexity O(N) for UTF-16 length.
# @param a allocator to use
# @param in input UTF-16 slice
# @returns UTF-8 string
# Converts a UTF-16 slice to an allocated UTF-8 string.
# @complexity O(N) for UTF-16 code units
# @throws failure for unpaired or malformed surrogates
# @ownership The caller owns the returned string and must free it with a.
# @example
#   text := try utf8.utf16to8(a, wide)
pub utf16to8(in u16[]) !$str:
    a := ctx.alloc
    n u64 = slices.count(in)
    if n == 0:
        ret try strings.alloc(0)
    ..

    outSize u64 = try utf16to8size(in)
    if outSize == 0:
        ret try strings.alloc(0)
    ..

    result str = try strings.alloc(outSize)
    onerror result.free()
    
    outPtr u8* = strings.toPtr(result)
    writePtr u8* = outPtr
    i u64 = 0

    loop i < n:
        writeSize u64 = try utf16to8iter(in, writePtr, addrof i, n)
        writePtr = cast.reinterpret[u8](cast.utop(cast.ptou(writePtr) + writeSize))
    ..

    ret move result
..

# Returns size in bytes of string, for UTF8 strings codepoint (UTF8 character) count may be
# different from byte size.
# @complexity O(N) depending on string size.
# @param s input string
# @returns size in bytes of string
# Counts Unicode scalar values in a UTF-8 string.
# @complexity O(N) for UTF-8 byte count
# @throws failure if s contains invalid UTF-8
# @example
#   length := try utf8.countCodepoints(text)
pub countCodepoints(s str) !u64:
    cnt u64 = 0
    it Utf8Iterator = iterator(s)

    loop it.hasData():
        try it.next()
        cnt = cnt + 1
    ..
    ret cnt
..
