mod main
use "std:allocator" as allocator
use "std:errors" as errors
use "std:heap" as heap
use "std:slices" as slices
use "std:strings" as strings
use "std:utf8" as utf8
pub main() !void:
    a allocator.Allocator = heap.allocator()
    iterator := utf8.iterator("A")
    if iterator.hasData() == false:
        throw errors.failure("utf8 iterator lost input")
    ..
    codepoint := try iterator.peek()
    advanced := try iterator.next()
    if codepoint.value != 65 || advanced.value != 65 || iterator.hasData():
        throw errors.failure("utf8 iterator changed")
    ..
    count := try utf8.countCodepoints("hé")
    if count != 2:
        throw errors.failure("utf8 count changed")
    ..
    wide := try utf8.utf8To16("hé")
    defer slices.free(wide)
    if slices.count(wide) != 2:
        throw errors.failure("utf8 conversion changed")
    ..
    wideNt := try utf8.utf8To16NT("A")
    defer slices.free(wideNt)
    wideNtPtr u16*
    # SAFETY: utf8To16NT allocates one trailing code unit beyond the returned
    # logical count for the null terminator.
    unsafe:
        wideNtPtr = slices.toPtr(wideNt)
        if slices.count(wideNt) != 1 || wideNtPtr[0] != 65 || wideNtPtr[1] != 0:
            throw errors.failure("null-terminated UTF-16 conversion changed")
        ..
    ..
    if try utf8.utf16to8size(wide) != "hé".countBytes():
        throw errors.failure("UTF-16 size calculation changed")
    ..
    roundTrip := try utf8.utf16to8(wide)
    defer roundTrip.free()
    roundTripPtr u8* = strings.toPtr(roundTrip)
    # SAFETY: owned strings reserve a terminator immediately after countBytes.
    unsafe:
        if roundTripPtr[roundTrip.countBytes()] != 0:
            throw errors.failure("UTF-8 result is not null terminated")
        ..
    ..
    encoded := [4]u8
    encodedView u8[] = slices.fromPtr(slices.toPtr(encoded), 4)
    if try utf8.encode(0x1F625, encodedView) != 4:
        throw errors.failure("supplementary UTF-8 encoding changed")
    ..
    decoded := try utf8.decode(encodedView)
    if decoded.value != 0x1F625 || decoded.width != 4:
        throw errors.failure("supplementary UTF-8 decoding changed")
    ..
    decoder := utf8.newDecoder()
    firstChunk u8[] = slices.fromPtr(slices.toPtr(encoded), 2)
    scalars := [1]u32
    scalarView u32[] = slices.fromPtr(slices.toPtr(scalars), 1)
    firstResult := try decoder.push(firstChunk, scalarView)
    if firstResult.needsInput == false || firstResult.written != 0:
        throw errors.failure("incremental UTF-8 decoder did not retain partial input")
    ..
    secondChunk u8[] = slices.fromPtr(addrof encoded[2], 2)
    secondResult := try decoder.push(secondChunk, scalarView)
    try decoder.finish()
    if secondResult.written != 1 || scalars[0] != 0x1F625:
        throw errors.failure("incremental UTF-8 decoding changed")
    ..
..
