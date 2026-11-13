mod main
use "std:allocator" as allocator
use "std:debug_alloc" as debug_alloc
use "std:errors" as errors
use "std:heap" as heap
use "std:strings" as strings
pub main() !void:
    a allocator.Allocator = heap.allocator()

    debug := try debug_alloc.newDefault(a)
    ctx.alloc = debug.allocator()
    provenance := try strings.copy("allocator provenance")
    ctx.alloc = a
    provenance.free()
    if debug.leakCount() != 0 || debug.stats().freeCalls != 1:
        debug.destroy()
        throw errors.failure("string did not retain its originating allocator")
    ..
    debug.destroy()

    copy := try strings.copy("magma")
    defer copy.free()
    if copy.countBytes() != 5 || strings.compare(copy, "magma") == false:
        throw errors.failure("strings behavior changed")
    ..
    if copy != "magma" || copy == "magmb" || "" != "":
        throw errors.failure("string equality operators changed")
    ..
    copyPtr u8* = strings.toPtr(copy)
    # SAFETY: copy allocates a trailing terminator at index countBytes.
    unsafe:
        if copyPtr[copy.countBytes()] != 0:
            throw errors.failure("copied string is not null terminated")
        ..
    ..
    empty := try strings.alloc(0)
    defer empty.free()
    emptyPtr u8* = strings.toPtr(empty)
    # SAFETY: strings.alloc always returns a terminated allocation.
    unsafe:
        if *emptyPtr != 0:
            throw errors.failure("empty allocated string is not null terminated")
        ..
    ..
    filled := try strings.allocFill(3, 65)
    defer filled.free()
    filledPtr u8* = strings.toPtr(filled)
    # SAFETY: allocFill appends a terminator after the requested payload.
    unsafe:
        if strings.byteAt(filled, 0) != 65 || filledPtr[3] != 0:
            throw errors.failure("filled string is not null terminated")
        ..
    ..
    cstr := try strings.toCstr("magma")
    defer a.free(cstr)
    # SAFETY: toCstr returns count+1 addressable bytes including the terminator.
    unsafe:
        if cstr[5] != 0:
            throw errors.failure("C string is not null terminated")
        ..
    ..

    noCopy := strings.toCstrNoCopy(copy)
    if noCopy != copyPtr || strings.cStrLen(noCopy) != 5:
        throw errors.failure("toCstrNoCopy rejected a terminated owned string")
    ..

    unterminated u8* = try a.alloc(5)
    defer a.free(unterminated)
    i u64 = 0
    # SAFETY: unterminated points to the five bytes allocated immediately above.
    unsafe:
        loop i < 5:
            unterminated[i] = 65
            i = i + 1
        ..
    ..
    borrowed str = strings.fromPtrNoCopy(unterminated, 5)
    borrowedPtr := strings.toCstrNoCopy(borrowed)
    if borrowedPtr != unterminated:
        throw errors.failure("toCstrNoCopy did not return the borrowed pointer")
    ..
    copiedFromPtr := try strings.fromPtr(unterminated, 5)
    defer copiedFromPtr.free()
    if copiedFromPtr.countBytes() != 5 || strings.toPtr(copiedFromPtr) == unterminated:
        throw errors.failure("fromPtr did not copy its input")
    ..
    borrowedCstr := strings.fromCstrNoCopy(cstr)
    ownedCstr := try strings.fromCstr(cstr)
    defer ownedCstr.free()
    if strings.compare(borrowedCstr, "magma") == false || strings.compare(ownedCstr, "magma") == false:
        throw errors.failure("C string conversion changed")
    ..

    if try strings.findByte("magma", 103) != 2 || try strings.find("one two", "two") != 4:
        throw errors.failure("string find changed")
    ..
    sub := try strings.substring("magma", 1, 4)
    defer sub.free()
    if strings.compare(sub, "agm") == false:
        throw errors.failure("substring changed")
    ..
    trimmed := try strings.trim(" \t magma \r\n")
    defer trimmed.free()
    withoutPrefix := try strings.trimPrefix("std:strings", "std:")
    defer withoutPrefix.free()
    withoutSuffix := try strings.trimSuffix("file.mg", ".mg")
    defer withoutSuffix.free()
    if strings.compare(trimmed, "magma") == false || strings.compare(withoutPrefix, "strings") == false || strings.compare(withoutSuffix, "file") == false:
        throw errors.failure("string trimming changed")
    ..

    parts := try strings.split("one::two::", "::")
    defer parts.free()
    if parts.count() != 3 || strings.compare(try parts.get(0), "one") == false || strings.compare(try parts.get(1), "two") == false || strings.compare(try parts.get(2), "") == false:
        throw errors.failure("eager split changed")
    ..

    splitPair := try strings.splitOnce("left=right", "=")
    defer:
        # SAFETY: splitOnce returns two uniquely owned string fields.
        unsafe:
            splitPair.first.free()
            splitPair.second.free()
        ..
    ..
    if strings.compare(splitPair.first, "left") == false || strings.compare(splitPair.second, "right") == false:
        throw errors.failure("splitOnce changed")
    ..

    splitIterator := try strings.splitIter("a,b,c", ",")
    defer splitIterator.free()
    iterFirst := try splitIterator.next()
    defer iterFirst.free()
    iterSecond := try splitIterator.next()
    defer iterSecond.free()
    iterThird := try splitIterator.next()
    defer iterThird.free()
    if splitIterator.hasData() || strings.compare(iterFirst, "a") == false || strings.compare(iterSecond, "b") == false || strings.compare(iterThird, "c") == false:
        throw errors.failure("split iterator changed")
    ..
..
