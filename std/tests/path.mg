mod main
use "std:errors" as errors
use "std:path" as path
use "std:strings" as strings
use "std:allocator" as allocator
use "std:heap" as heap
pub main() !void:
    a allocator.Allocator = heap.allocator()
    separator := path.separator()
    if path.isSeparator(separator) == false:
        throw errors.failure("native path separator was not recognized")
    ..
    if separator == 92:
        if path.isAbsolute("C:\\tmp") == false:
            throw errors.failure("absolute Windows path was not recognized")
        ..
        if path.isAbsolute("C:tmp"):
            throw errors.failure("drive-relative Windows path treated as absolute")
        ..
        unc := try path.normalize("\\\\server\\share\\folder\\..")
        defer unc.free()
        if strings.compare(unc, "\\\\server\\share") == false:
            throw errors.failure("UNC normalization changed its root")
        ..
    elif path.isAbsolute("/tmp") == false:
        throw errors.failure("absolute Unix path was not recognized")
    ..
    base := try path.base("one/two.txt")
    defer base.free()
    # SAFETY: owned strings reserve a terminator immediately after countBytes.
    unsafe:
        if strings.compare(base, "two.txt") == false || strings.toPtr(base)[base.countBytes()] != 0:
            throw errors.failure("path base changed")
        ..
    ..
    extension := try path.extension("one/two.txt")
    defer extension.free()
    # SAFETY: owned strings reserve a terminator immediately after countBytes.
    unsafe:
        if strings.compare(extension, ".txt") == false || strings.toPtr(extension)[extension.countBytes()] != 0:
            throw errors.failure("path extension changed")
        ..
    ..
    noExtension := try path.extension("README")
    defer noExtension.free()
    # SAFETY: even an empty owned string has its allocated terminator byte.
    unsafe:
        if noExtension.countBytes() != 0 || *strings.toPtr(noExtension) != 0:
            throw errors.failure("empty path extension is not null terminated")
        ..
    ..

    parts := [3]str
    parts[0] = "one"
    parts[1] = "two"
    parts[2] = ".."
    joined := try path.join(parts)
    defer joined.free()
    if strings.compare(joined, "one") == false:
        throw errors.failure("path join did not normalize components")
    ..
    normalized := try path.normalize("one//./two/../three")
    defer normalized.free()
    expected str = "one/three"
    if separator == 92:
        expected = "one\\three"
    ..
    if strings.compare(normalized, expected) == false:
        throw errors.failure("path normalization changed")
    ..
    parent := try path.parent("one/two/file.txt")
    defer parent.free()
    expectedParent str = "one/two"
    if separator == 92:
        expectedParent = "one\\two"
    ..
    if strings.compare(parent, expectedParent) == false:
        throw errors.failure("path parent changed")
    ..
    stem := try path.stem("archive.tar.gz")
    defer stem.free()
    if strings.compare(stem, "archive.tar") == false:
        throw errors.failure("path stem changed")
    ..
    changed := try path.changeExtension("archive.tar.gz", "zip")
    defer changed.free()
    if strings.compare(changed, "archive.tar.zip") == false:
        throw errors.failure("path extension replacement changed")
    ..
..
