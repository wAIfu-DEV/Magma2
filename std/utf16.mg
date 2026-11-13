mod utf16
# Validated UTF-16 iteration, conversion, lossy recovery, and byte decoding.

use "std:allocator" as alc
use "std:cast" as cast
use "std:checked" as checked
use "std:errors" as errors
use "std:footgun" as footgun
use "std:slices" as slices
use "std:strings" as strings
use "std:unicode" as unicode
use "std:utf8" as utf8

pub const ENDIAN_LITTLE u8 = 1
pub const ENDIAN_BIG u8 = 2
pub const ENDIAN_BOM u8 = 3
pub const BOM_NONE u8 = 0
pub const BOM_LITTLE u8 = ENDIAN_LITTLE
pub const BOM_BIG u8 = ENDIAN_BIG

# A decoded scalar and its width in UTF-16 code units.
pub Codepoint(value u32, width u8)

# A borrowed iterator over UTF-16 code units.
pub Utf16Iterator(data u16[], index u64)

# Progress from incremental raw-byte decoding.
pub DecodeResult(consumed u64, written u64, needsInput bool, needsOutput bool)

# Incremental raw UTF-16 decoder with bounded partial-input state.
pub Decoder(
    endian u8
    selectedEndian u8
    pendingByte u8
    hasPendingByte bool
    pendingUnit u16
    hasPendingUnit bool
    pendingHigh u16
    hasPendingHigh bool
)

# Creates an incremental decoder for explicit or BOM-selected byte order.
pub newDecoder(endian u8) !Decoder:
    if endian != ENDIAN_LITTLE && endian != ENDIAN_BIG && endian != ENDIAN_BOM:
        throw errors.invalidArgument("invalid UTF-16 byte order")
    ..
    selected u8 = endian
    if endian == ENDIAN_BOM:
        selected = BOM_NONE
    ..
    ret Decoder(
        endian=endian,
        selectedEndian=selected,
        pendingByte=0,
        hasPendingByte=false,
        pendingUnit=0,
        hasPendingUnit=false,
        pendingHigh=0,
        hasPendingHigh=false,
    )
..

Decoder.acceptPair(first u8, second u8) !void:
    if this.selectedEndian == BOM_NONE:
        if first == 0xFF && second == 0xFE:
            this.selectedEndian = ENDIAN_LITTLE
            ret
        ..
        if first == 0xFE && second == 0xFF:
            this.selectedEndian = ENDIAN_BIG
            ret
        ..
        throw errors.failure("UTF-16 byte stream has no BOM")
    ..
    firstWide := cast.u8to64(first)
    secondWide := cast.u8to64(second)
    if this.selectedEndian == ENDIAN_LITTLE:
        this.pendingUnit = cast.u64to16(firstWide | (secondWide << 8))
    else:
        this.pendingUnit = cast.u64to16((firstWide << 8) | secondWide)
    ..
    this.hasPendingUnit = true
..

# Decodes chunked UTF-16 bytes into Unicode scalar values.
pub Decoder.push(input u8[], output u32[]) !DecodeResult:
    consumed u64 = 0
    written u64 = 0
    loop true:
        if this.hasPendingUnit:
            unit := this.pendingUnit
            if this.hasPendingHigh:
                if unicode.isLowSurrogate(unit) == false:
                    throw errors.failure("invalid UTF-16 surrogate pair")
                ..
                if written >= slices.count(output):
                    ret DecodeResult(consumed=consumed, written=written, needsInput=false, needsOutput=true)
                ..
                output[written] = try unicode.combineSurrogates(this.pendingHigh, unit)
                written = written + 1
                this.hasPendingHigh = false
                this.hasPendingUnit = false
                continue
            ..
            if unicode.isHighSurrogate(unit):
                this.pendingHigh = unit
                this.hasPendingHigh = true
                this.hasPendingUnit = false
                continue
            ..
            if unicode.isLowSurrogate(unit):
                throw errors.failure("unexpected low UTF-16 surrogate")
            ..
            if written >= slices.count(output):
                ret DecodeResult(consumed=consumed, written=written, needsInput=false, needsOutput=true)
            ..
            output[written] = cast.u64to32(cast.u16to64(unit))
            written = written + 1
            this.hasPendingUnit = false
            continue
        ..

        if consumed >= slices.count(input):
            needsMore := this.hasPendingByte || this.hasPendingHigh || this.selectedEndian == BOM_NONE
            ret DecodeResult(consumed=consumed, written=written, needsInput=needsMore, needsOutput=false)
        ..
        if this.hasPendingByte == false:
            this.pendingByte = input[consumed]
            this.hasPendingByte = true
            consumed = consumed + 1
            continue
        ..
        second := input[consumed]
        consumed = consumed + 1
        first := this.pendingByte
        this.hasPendingByte = false
        try this.acceptPair(first, second)
    ..
..

# Verifies that the byte stream ended at a scalar boundary.
pub Decoder.finish() !void:
    if this.selectedEndian == BOM_NONE:
        throw errors.failure("UTF-16 byte stream has no BOM")
    ..
    if this.hasPendingByte || this.hasPendingUnit || this.hasPendingHigh:
        throw errors.failure("incomplete UTF-16 sequence at end of input")
    ..
..

# Decodes the first scalar from a UTF-16 slice.
# @complexity O(1)
pub decode(units u16[]) !Codepoint:
    count := slices.count(units)
    if count == 0:
        throw errors.failure("cannot decode empty UTF-16 input")
    ..
    first := units[0]
    if unicode.isHighSurrogate(first):
        if count < 2 || unicode.isLowSurrogate(units[1]) == false:
            throw errors.failure("invalid UTF-16 surrogate pair")
        ..
        ret Codepoint(value=try unicode.combineSurrogates(first, units[1]), width=2)
    ..
    if unicode.isLowSurrogate(first):
        throw errors.failure("unexpected low UTF-16 surrogate")
    ..
    ret Codepoint(value=cast.u64to32(cast.u16to64(first)), width=1)
..

# Creates a borrowed UTF-16 iterator.
pub iterator(units u16[]) Utf16Iterator:
    ret Utf16Iterator(data=units, index=0)
..

Utf16Iterator.hasData() bool:
    ret this.index < slices.count(this.data)
..

Utf16Iterator.peek() !Codepoint:
    if this.hasData() == false:
        throw errors.failure("UTF-16 iterator is exhausted")
    ..
    remaining := slices.fromPtr(cast.utop(cast.ptou(slices.toPtr(this.data)) + this.index * sizeof u16), slices.count(this.data) - this.index)
    ret try decode(remaining)
..

Utf16Iterator.next() !Codepoint:
    cp := try this.peek()
    this.index = this.index + cast.u8to64(cp.width)
    ret cp
..

# Reports whether every code unit belongs to a valid scalar sequence.
pub validate(units u16[]) bool:
    it := iterator(units)
    loop it.hasData():
        cp, e := it.next()
        if e.nok():
            ret false
        ..
    ..
    ret true
..

# Returns the number of code units required for cp.
pub encodedSize(cp u32) !u64:
    if unicode.isScalar(cp) == false:
        throw errors.invalidArgument("invalid Unicode scalar value")
    ..
    if cp < 0x10000:
        ret 1
    ..
    ret 2
..

# Encodes one scalar into caller-provided UTF-16 storage.
pub encode(cp u32, output u16[]) !u64:
    needed := try encodedSize(cp)
    if slices.count(output) < needed:
        throw errors.invalidArgument("UTF-16 output buffer is too small")
    ..
    if needed == 1:
        output[0] = cast.u64to16(cast.u32to64(cp))
        ret 1
    ..
    pair := try unicode.splitSurrogate(cp)
    # needed is two on this path and the capacity guard establishes both slots.
    bounded 0 < slices.count(output), 1 < slices.count(output):
        output[0] = pair.high
        output[1] = pair.low
    ..
    ret 2
..

# Converts validated UTF-16 to an owned UTF-8 string.
pub toUtf8(a alc.Allocator, units u16[]) !$str:
    ret try utf8.utf16to8(units)
..

# Converts validated UTF-8 to owned UTF-16 code units.
pub fromUtf8(a alc.Allocator, text str) !$u16[]:
    ret try utf8.utf8To16(text)
..

# Returns the UTF-8 byte count required for validated UTF-16.
pub toUtf8Size(units u16[]) !u64:
    ret try utf8.utf16to8size(units)
..

# Returns the UTF-16 code-unit count required for validated UTF-8.
pub fromUtf8Size(text str) !u64:
    converted := try fromUtf8SizeUsingIterator(text)
    ret converted
..

fromUtf8SizeUsingIterator(text str) !u64:
    it := utf8.iterator(text)
    total u64 = 0
    loop it.hasData():
        cp := try it.next()
        total = try checked.uAdd(total, try encodedSize(cp.value))
    ..
    ret total
..

# Converts malformed UTF-16 by replacing each unpaired surrogate with U+FFFD.
pub toUtf8Lossy(a alc.Allocator, units u16[]) !$str:
    maximum := try checked.uMul(slices.count(units), 3)
    owned $str = try strings.alloc(maximum)
    onerror owned.free()
    out := strings.toPtr(owned)
    inputIndex u64 = 0
    outputIndex u64 = 0
    count := slices.count(units)
    loop inputIndex < count:
        cp u32 = unicode.REPLACEMENT
        first := units[inputIndex]
        if unicode.isHighSurrogate(first) && inputIndex + 1 < count && unicode.isLowSurrogate(units[inputIndex + 1]):
            cp = try unicode.combineSurrogates(first, units[inputIndex + 1])
            inputIndex = inputIndex + 2
        elif unicode.isHighSurrogate(first) || unicode.isLowSurrogate(first):
            inputIndex = inputIndex + 1
        else:
            cp = cast.u64to32(cast.u16to64(first))
            inputIndex = inputIndex + 1
        ..
        remaining := slices.fromPtr(cast.utop(cast.ptou(out) + outputIndex), maximum - outputIndex)
        outputIndex = outputIndex + try utf8.encode(cp, remaining)
    ..
    # SAFETY: maximum includes the reserved trailing terminator and outputIndex
    # never exceeds the encoded prefix computed above.
    unsafe:
        out[outputIndex] = 0
    ..
    result := strings.fromPtrNoCopy(out, outputIndex)
    footgun.drop[str](move owned)
    ret result
..

# Converts malformed UTF-8 by replacing invalid bytes with U+FFFD.
pub fromUtf8Lossy(a alc.Allocator, text str) !$u16[]:
    inputCount := text.countBytes()
    if inputCount == 0:
        ret slices.fromPtr(none, 0)
    ..
    out u16* = try a.allocT[u16](inputCount)
    onerror a.free(out)
    input := strings.toPtr(text)
    inputIndex u64 = 0
    outputIndex u64 = 0
    loop inputIndex < inputCount:
        remaining := slices.fromPtr(cast.utop(cast.ptou(input) + inputIndex), inputCount - inputIndex)
        decoded, decodeError := utf8.decode(remaining)
        cp u32 = unicode.REPLACEMENT
        width u64 = 1
        if decodeError.ok():
            cp = decoded.value
            width = cast.u8to64(decoded.width)
        ..
        output := slices.fromPtr(cast.utop(cast.ptou(out) + outputIndex * sizeof u16), inputCount - outputIndex)
        outputIndex = outputIndex + try encode(cp, output)
        inputIndex = inputIndex + width
    ..
    ret slices.fromPtr(out, outputIndex)
..

# Detects a leading UTF-16 BOM in raw bytes.
pub detectBom(bytes u8[]) u8:
    if slices.count(bytes) < 2:
        ret BOM_NONE
    ..
    if bytes[0] == 0xFF && bytes[1] == 0xFE:
        ret BOM_LITTLE
    ..
    if bytes[0] == 0xFE && bytes[1] == 0xFF:
        ret BOM_BIG
    ..
    ret BOM_NONE
..

# Decodes raw UTF-16 bytes, optionally selecting endianness from a BOM.
# BOM-selected decoding consumes the BOM; explicit-endian decoding does not.
pub decodeBytes(a alc.Allocator, bytes u8[], endian u8) !$u16[]:
    byteCount := slices.count(bytes)
    if (byteCount & 1) != 0:
        throw errors.failure("UTF-16 byte input has an incomplete code unit")
    ..
    offset u64 = 0
    selected := endian
    if endian == ENDIAN_BOM:
        selected = detectBom(bytes)
        if selected == BOM_NONE:
            throw errors.failure("UTF-16 byte input has no BOM")
        ..
        offset = 2
    elif endian != ENDIAN_LITTLE && endian != ENDIAN_BIG:
        throw errors.invalidArgument("invalid UTF-16 byte order")
    ..
    count := (byteCount - offset) / 2
    if count == 0:
        ret slices.fromPtr(none, 0)
    ..
    result := try slices.alloc[u16](count)
    onerror slices.free(result)
    for i u64 = 0 to count:
        at := offset + i * 2
        # count=(byteCount-offset)/2 establishes both source bytes; result was
        # allocated with exactly count code-unit slots.
        bounded at < slices.count(bytes), at + 1 < slices.count(bytes), i < slices.count(result):
            first := cast.u8to64(bytes[at])
            second := cast.u8to64(bytes[at + 1])
            if selected == ENDIAN_LITTLE:
                result[i] = cast.u64to16(first | (second << 8))
            else:
                result[i] = cast.u64to16((first << 8) | second)
            ..
        ..
    ..
    if validate(result) == false:
        throw errors.failure("invalid UTF-16 byte input")
    ..
    ret result
..
