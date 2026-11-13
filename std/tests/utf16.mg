mod main

use "std:errors" as errors
use "std:heap" as heap
use "std:slices" as slices
use "std:utf16" as utf16

pub main() !void:
    a := heap.allocator()
    units := [3]u16
    units[0] = 0x41
    units[1] = 0xD83D
    units[2] = 0xDE25
    view u16[] = slices.fromPtr(slices.toPtr(units), 3)
    if utf16.validate(view) == false:
        throw errors.failure("valid UTF-16 rejected")
    ..
    it := utf16.iterator(view)
    first := try it.next()
    second := try it.next()
    if first.value != 0x41 || first.width != 1 || second.value != 0x1F625 || second.width != 2:
        throw errors.failure("UTF-16 iteration changed")
    ..
    encoded := [2]u16
    encodedView u16[] = slices.fromPtr(slices.toPtr(encoded), 2)
    if try utf16.encode(0x1F625, encodedView) != 2 || encoded[0] != 0xD83D || encoded[1] != 0xDE25:
        throw errors.failure("UTF-16 scalar encoding changed")
    ..
    text := try utf16.toUtf8(a, view)
    defer text.free()
    roundTrip := try utf16.fromUtf8(a, text)
    defer slices.free(roundTrip)
    if slices.count(roundTrip) != 3:
        throw errors.failure("UTF-16 round trip changed")
    ..
    raw := [6]u8
    raw[0] = 0xFF
    raw[1] = 0xFE
    raw[2] = 0x41
    raw[3] = 0
    raw[4] = 0xA9
    raw[5] = 0x03
    rawView u8[] = slices.fromPtr(slices.toPtr(raw), 6)
    decoded := try utf16.decodeBytes(a, rawView, utf16.ENDIAN_BOM)
    defer slices.free(decoded)
    if slices.count(decoded) != 2 || decoded[0] != 0x41 || decoded[1] != 0x03A9:
        throw errors.failure("UTF-16 endian decoding changed")
    ..
    malformed := [1]u16
    malformed[0] = 0xD800
    malformedView u16[] = slices.fromPtr(slices.toPtr(malformed), 1)
    if utf16.validate(malformedView):
        throw errors.failure("malformed UTF-16 accepted")
    ..
    lossy := try utf16.toUtf8Lossy(a, malformedView)
    defer lossy.free()
    if lossy.countBytes() != 3:
        throw errors.failure("lossy UTF-16 replacement changed")
    ..
    decoder := try utf16.newDecoder(utf16.ENDIAN_BOM)
    scalars := [2]u32
    scalarView u32[] = slices.fromPtr(slices.toPtr(scalars), 2)
    firstBytes u8[] = slices.fromPtr(slices.toPtr(raw), 3)
    firstResult := try decoder.push(firstBytes, scalarView)
    if firstResult.needsInput == false || firstResult.written != 0:
        throw errors.failure("incremental UTF-16 decoder did not retain partial input")
    ..
    remainingBytes u8[] = slices.fromPtr(addrof raw[3], 3)
    secondResult := try decoder.push(remainingBytes, scalarView)
    try decoder.finish()
    if secondResult.written != 2 || scalars[0] != 0x41 || scalars[1] != 0x03A9:
        throw errors.failure("incremental UTF-16 decoding changed")
    ..
..
