mod path
# Platform-aware lexical path inspection and component extraction.

use "std:strings" as strings
use "std:cast" as cast
use "std:allocator" as allocator
use "std:array" as array
use "std:builder" as builder

@platform("windows")
use "std:win/path_impl" as impl_path

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/path_impl" as impl_path

# Returns the preferred path-separator byte for the current platform.
# @complexity O(1)
# @example
#   separator := path.separator()
pub separator() u8:
    ret impl_path.separator()
..

# Reports whether c is a slash or backslash accepted as a path separator.
# @complexity O(1)
# @example
#   isBoundary := path.isSeparator(character)
pub isSeparator(c u8) bool:
    ret c == 47 || c == 92
..

# Reports whether path is absolute according to current-platform rules.
# @complexity O(1)
# @example
#   absolute := path.isAbsolute("/tmp/data")
pub isAbsolute(path str) bool:
    n := path.countBytes()
    if n == 0:
        ret false
    ..
    ret impl_path.isAbsolute(path)
..

# Allocates the final non-separator component of path.
# Trailing separators are ignored; an all-separator path produces an empty string.
# @complexity O(N)
# @param a allocator for the returned string
# @param path path to inspect
# @returns owned final path component
# @ownership Release the result with the same allocator.
# @example
#   name := try path.base(a, "/tmp/archive.tar")
pub base(path str) !$str:
    a := ctx.alloc
    n := path.countBytes()
    end := n
    loop end > 0 && isSeparator(strings.byteAt(path, end - 1)):
        end = end - 1
    ..
    start := end
    loop start > 0 && isSeparator(strings.byteAt(path, start - 1)) == false:
        start = start - 1
    ..
    p := cast.utop(cast.ptou(strings.toPtr(path)) + start)
    ret try strings.fromPtr(p, end - start)
..

# Returns the suffix beginning at the final dot in the base name. The base
# before that suffix may be empty, so ".gitignore" has extension ".gitignore".
# @complexity O(N)
# @param a allocator for the returned string
# @param path path to inspect
# @returns owned extension including the dot, or an empty string
# @ownership Release the result with the same allocator.
# @example
#   ext := try path.extension(a, "archive.tar.gz")
pub extension(path str) !$str:
    a := ctx.alloc
    temporary := ctx.alloc
    b := try base(path)
    defer b.free()
    n := b.countBytes()
    i := n
    loop i > 0:
        i = i - 1
        if strings.byteAt(b, i) == 46:
            p := cast.utop(cast.ptou(strings.toPtr(b)) + i)
            ret try strings.fromPtr(p, n - i)
        ..
    ..
    ret try strings.alloc(0)
..

Component(
    value str
)

borrowRange(value str, start u64, end u64) str:
    p := cast.utop(cast.ptou(strings.toPtr(value)) + start)
    ret strings.fromPtrNoCopy(p, end - start)
..

# Joins path components and normalizes the result. An absolute component
# discards components accumulated before it.
pub join(parts str[]) !$str:
    a := ctx.alloc
    temporary := ctx.alloc
    out := try builder.new()
    defer out.free()
    for i u64 = 0 to parts.count():
        part := parts[i]
        if part.countBytes() > 0:
            if out.isEmpty() == false && isAbsolute(part) == false:
                try out.addByte(separator())
            elif isAbsolute(part):
                try out.reset()
            ..
            try out.appendBorrowed(part)
        ..
    ..
    combined := try out.build()
    defer combined.free()
    ret try normalize(combined)
..

# Lexically normalizes separators, dot components, and resolvable parent
# components without accessing the filesystem.
pub normalize(value str) !$str:
    a := ctx.alloc
    temporary := ctx.alloc
    components := try array.new[Component](temporary)
    defer components.free(temporary, none)
    n := value.countBytes()
    absolute := isAbsolute(value)
    unc bool = n >= 2 && isSeparator(strings.byteAt(value, 0)) && isSeparator(strings.byteAt(value, 1))
    prefixEnd u64 = 0
    if n >= 2 && strings.byteAt(value, 1) == 58:
        prefixEnd = 2
    ..
    i := prefixEnd
    loop i < n && isSeparator(strings.byteAt(value, i)):
        i = i + 1
    ..
    loop i < n:
        start := i
        loop i < n && isSeparator(strings.byteAt(value, i)) == false:
            i = i + 1
        ..
        component := borrowRange(value, start, i)
        if strings.compare(component, ".") == false && component.countBytes() != 0:
            if strings.compare(component, ".."):
                count := components.count()
                if count > 0 && strings.compare(components.view()[count - 1].value, "..") == false:
                    ignored := try components.popRight(a)
                elif absolute == false:
                    try components.pushRight(a, Component(value=component))
                ..
            else:
                try components.pushRight(a, Component(value=component))
            ..
        ..
        loop i < n && isSeparator(strings.byteAt(value, i)):
            i = i + 1
        ..
    ..

    out := try builder.new()
    defer out.free()
    if prefixEnd == 2:
        try out.appendBorrowed(borrowRange(value, 0, 2))
    ..
    if absolute:
        try out.addByte(separator())
        if unc:
            try out.addByte(separator())
        ..
    ..
    items := components.view()
    for j u64 = 0 to items.count():
        if j > 0:
            try out.addByte(separator())
        ..
        try out.appendBorrowed(items[j].value)
    ..
    if out.isEmpty():
        ret try strings.copy(".")
    ..
    ret try out.build()
..

# Returns the lexical parent of a path.
pub parent(value str) !$str:
    a := ctx.alloc
    temporary := ctx.alloc
    normalized := try normalize(value)
    defer normalized.free()
    n := normalized.countBytes()
    if isAbsolute(normalized) && (n == 1 || (n == 3 && strings.byteAt(normalized, 1) == 58)):
        ret try strings.copy(normalized)
    ..
    end := n
    loop end > 0 && isSeparator(strings.byteAt(normalized, end - 1)):
        end = end - 1
    ..
    loop end > 0 && isSeparator(strings.byteAt(normalized, end - 1)) == false:
        end = end - 1
    ..
    loop end > 1 && isSeparator(strings.byteAt(normalized, end - 1)):
        end = end - 1
    ..
    if end == 0:
        ret try strings.copy(".")
    ..
    ret try strings.substring(normalized, 0, end)
..

# Returns the base name without its final extension.
pub stem(value str) !$str:
    a := ctx.alloc
    temporary := ctx.alloc
    b := try base(value)
    defer b.free()
    n := b.countBytes()
    i := n
    loop i > 0:
        i = i - 1
        if strings.byteAt(b, i) == 46:
            ret try strings.substring(b, 0, i)
        ..
    ..
    ret try strings.copy(b)
..

# Replaces the final extension. extension may be empty and may include its dot.
pub changeExtension(value str, newExtension str) !$str:
    a := ctx.alloc
    temporary := ctx.alloc
    oldExtension := try extension(value)
    defer oldExtension.free()
    keep := value.countBytes() - oldExtension.countBytes()
    out := try builder.new()
    defer out.free()
    try out.appendBorrowed(borrowRange(value, 0, keep))
    if newExtension.countBytes() > 0:
        if strings.byteAt(newExtension, 0) != 46:
            try out.addByte(46)
        ..
        try out.appendBorrowed(newExtension)
    ..
    ret try out.build()
..
