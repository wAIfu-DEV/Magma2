mod fs
# Portable whole-file operations and recursive directory traversal.

use "std:allocator" as alc
use "std:file" as file
use "std:strings" as strings
use "std:errors" as errors
use "std:path" as path_util
use "std:iterator" as iterator

@platform("windows")
use "std:win/fs_impl" as impl_fs

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/fs_impl" as impl_fs

# Reads an entire file into an owned string.
# @complexity O(N), where N is the file size
# @param a allocator for the returned contents
# @param path file to read
# @returns owned file contents
# @ownership Release the result with the same allocator.
# @example
#   contents := try fs.readFile(a, "settings.json")
pub readFile(path str) !$str:
    a := ctx.alloc
    mode := file.mode()
    mode = mode.read()
    f := try file.open(path, mode)
    defer f.close()
    count := try f.count()
    r := try f.reader()
    ret try r.read(count)
..

# Reads at most count bytes starting at offset without exposing or mutating a
# persistent file cursor. Platform-specific positional handles remain private.
pub readRange(path str, offset u64, count u64) !$str:
    a := ctx.alloc
    output := try strings.alloc(count)
    onerror output.free()
    written := try impl_fs.readRange(path, strings.toPtr(output), count, offset)
    if written > count:
        throw errors.failure("platform range read exceeded its destination")
    ..
    strings.truncate(addrof output, written)
    ret move output
..

# Replaces a file with the complete contents, creating it when absent.
# @complexity O(N), where N is the content byte length
# @param a allocator used for platform path conversion
# @param path destination file
# @param contents bytes to write
# @warning Existing contents are truncated.
# @example
#   try fs.writeFile(a, "output.txt", "complete")
pub writeFile(path str, contents str) !void:
    a := ctx.alloc
    mode := file.mode()
    mode = mode.write().create().truncate()
    f := try file.open(path, mode)
    defer f.close()
    w := try f.writer()
    written := try w.write(contents)
    if written != contents.countBytes():
        throw errors.failure("short file write")
    ..
..

# Deletes one file. Directories are rejected.
# @complexity O(1), excluding filesystem cost
# @example
#   try fs.removeFile(a, "obsolete.tmp")
pub removeFile(path str) !void:
    a := ctx.alloc
    try impl_fs.removeFile(path)
..

# Recursively visits every descendant of root. The path passed to visit is
# borrowed and remains valid only for the duration of the callback.
# @complexity O(E), where E is the number of visited entries
# @param a allocator used during traversal
# @param root directory whose descendants are visited
# @param visit callback receiving a borrowed path and directory flag
# @example
#   try fs.walk(a, root, visitEntry)
pub walk(root str, visit fn(str, bool) !void) !void:
    a := ctx.alloc
    try impl_fs.walk(root, visit)
..

pub const KIND_FILE u8 = 1
pub const KIND_DIR u8 = 2
pub const KIND_SYMLINK u8 = 3
pub const KIND_OTHER u8 = 4

pub FileKind(
    value u8
)

pub FileKind.isFile() bool:
    ret this.value == KIND_FILE
..

pub FileKind.isDir() bool:
    ret this.value == KIND_DIR
..

pub FileKind.isSymbolicLink() bool:
    ret this.value == KIND_SYMLINK
..

pub FileKind.isOther() bool:
    ret this.value == KIND_OTHER
..

pub Permissions(
    bits u32
)

pub Permissions.readable() bool:
    ret (this.bits & 1) != 0
..

pub Permissions.writable() bool:
    ret (this.bits & 2) != 0
..

pub Permissions.executable() bool:
    ret (this.bits & 4) != 0
..

pub Metadata(
    kindValue FileKind
    sizeValue u64
    permissionsValue Permissions
    modifiedValue i64
)

pub Metadata.kind() FileKind:
    ret this.kindValue
..

pub Metadata.size() u64:
    ret this.sizeValue
..

pub Metadata.permissions() Permissions:
    ret this.permissionsValue
..

pub Metadata.modified() i64:
    ret this.modifiedValue
..

pub metadata(path str) !Metadata:
    a := ctx.alloc
    native := try impl_fs.metadata(path, true)
    ret Metadata(
        kindValue=FileKind(value=native.kind),
        sizeValue=native.size,
        permissionsValue=Permissions(bits=native.permissions),
        modifiedValue=native.modified,
    )
..

pub linkMetadata(path str) !Metadata:
    a := ctx.alloc
    native := try impl_fs.metadata(path, false)
    ret Metadata(
        kindValue=FileKind(value=native.kind),
        sizeValue=native.size,
        permissionsValue=Permissions(bits=native.permissions),
        modifiedValue=native.modified,
    )
..

pub setPermissions(path str, permissions Permissions) !void:
    a := ctx.alloc
    try impl_fs.setPermissions(path, permissions.bits)
..

pub Entry(
    nameValue str
    kindValue FileKind
)

pub Entry.name() str:
    ret this.nameValue
..

pub Entry.kind() FileKind:
    ret this.kindValue
..

pub Dir(
    native impl_fs.Dir
)

pub openDir(path str) !$Dir:
    a := ctx.alloc
    native := try impl_fs.openDir(path)
    ret Dir(native=move native)
..

pub Dir.hasData() bool:
    ret this.native.hasData()
..

pub Dir.next() !$Entry:
    nativeEntry := try this.native.next()
    ret Entry(
        nameValue=nativeEntry.name,
        kindValue=FileKind(value=nativeEntry.kind),
    )
..

dirIteratorHasData(implementation ptr, index u64) bool:
    # SAFETY: Dir.iterator stores its live receiver as the iterator context.
    unsafe:
        directory Dir* = implementation
        ret directory.hasData()
    ..
..

dirIteratorNext(implementation ptr, index u64) !Entry:
    # SAFETY: Dir.iterator stores its live receiver as the iterator context.
    unsafe:
        directory Dir* = implementation
        ret try directory.next()
    ..
..

# Returns a generic iterator borrowing this open directory. The Dir must remain
# alive and open until iteration finishes.
pub Dir.iterator() iterator.Iterator[Entry]:
    ret iterator.new[Entry](this, dirIteratorHasData, dirIteratorNext)
..

destr Dir.close() !void:
    try this.native.close()
..

pub WalkOptions(
    followLinks bool
    includeRoot bool
)

walkEntriesInner(root str, options WalkOptions, visit fn(str, Metadata) !void) !void:
    a := ctx.alloc
    directory := try openDir(root)
    defer directory.close()
    loop directory.hasData():
        entry := try directory.next()
        parts := [2]str
        parts[0] = root
        parts[1] = entry.name()
        child := try path_util.join(parts)
        defer child.free()
        info := try linkMetadata(child)
        try visit(child, info)
        if info.kind().isDir():
            try walkEntriesInner(child, options, visit)
        elif info.kind().isSymbolicLink() && options.followLinks:
            followed := try metadata(child)
            if followed.kind().isDir():
                try walkEntriesInner(child, options, visit)
            ..
        ..
    ..
..

pub walkWithOptions(root str, options WalkOptions, visit fn(str, Metadata) !void) !void:
    a := ctx.alloc
    if options.includeRoot:
        try visit(root, try linkMetadata(root))
    ..
    try walkEntriesInner(root, options, visit)
..

pub walkDefault(root str, visit fn(str, Metadata) !void) !void:
    a := ctx.alloc
    try walkWithOptions(root, WalkOptions(followLinks=false, includeRoot=false), visit)
..

pub makeDir(path str) !void:
    a := ctx.alloc
    try impl_fs.makeDir(path)
..

pub makeDirs(path str) !void:
    a := ctx.alloc
    existing Metadata, existingError error = metadata(path)
    if existingError.ok():
        if existing.kind().isDir():
            ret
        ..
        throw errors.invalidArgument("path exists and is not a directory")
    ..
    parent := try path_util.parent(path)
    defer parent.free()
    if strings.compare(parent, path) == false && strings.compare(parent, ".") == false:
        try makeDirs(parent)
    ..
    try makeDir(path)
..

pub removeDir(path str) !void:
    a := ctx.alloc
    try impl_fs.removeDir(path)
..

pub removeTree(root str) !void:
    a := ctx.alloc
    info := try linkMetadata(root)
    if info.kind().isDir() == false:
        try removeFile(root)
        ret
    ..
    try removeTreeContents(root)
    try removeDir(root)
..

removeTreeContents(root str) !void:
    a := ctx.alloc
    directory := try openDir(root)
    defer directory.close()
    loop directory.hasData():
        entry := try directory.next()
        parts := [2]str
        parts[0] = root
        parts[1] = entry.name()
        child := try path_util.join(parts)
        defer child.free()
        try removeTree(child)
    ..
..

pub rename(source str, destination str) !void:
    a := ctx.alloc
    try impl_fs.rename(source, destination)
..

pub replace(source str, destination str) !void:
    a := ctx.alloc
    try impl_fs.replace(source, destination)
..

pub copyFile(source str, destination str) !void:
    a := ctx.alloc
    sourceInfo := try metadata(source)
    try impl_fs.copyFile(source, destination)
    try setPermissions(destination, sourceInfo.permissions())
..

pub currentDir() !$str:
    a := ctx.alloc
    ret try impl_fs.currentDir()
..

pub setCurrentDir(path str) !void:
    a := ctx.alloc
    try impl_fs.setCurrentDir(path)
..

pub temporaryDir() !$str:
    a := ctx.alloc
    ret try impl_fs.temporaryDir()
..

pub canonicalize(path str) !$str:
    a := ctx.alloc
    ret try impl_fs.canonicalize(path)
..
