mod file
# Portable file handles with reader, writer, seeking, and explicit cleanup.

use "std:allocator" as alc
use "std:errors"    as errors
use "std:writer"    as w
use "std:reader"    as r
use "std:file_op_mode" as fopm
use "std:cast"      as cast
use "std:future"    as future
use "std:abort"     as abort
use "std:strings"   as strings
use "std:slices"    as slices

@platform("windows")
use "std:win/file_impl" as impl_file

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/file_impl" as impl_file

# File handle wrapper and state.
# @complexity O(1).
pub File impl r.Reader w.Writer(
    handle ptr
    openMode fopm.OpenMode
    open bool
)

ReadTask(
    file File*
    allocator alc.Allocator
    offset u64
    count u64
    external abort.Signal
    hasExternal bool
)

# Closes the file if open.
# @complexity O(1).
# @example
#   try handle.close()
destr File.close() !void:
    if this.open:
        try impl_file.closeFile(this.handle)
        this.open = false
    ..
..

# Writes bytes to an open file handle.
# @complexity O(N) for byte count.
write(f File*, bytes str) !u64:
    if f.open == false:
        throw errors.invalidArgument("write to closed file")
    ..
    ret try impl_file.write(f.handle, bytes)
..

File.writeRaw(bytes str) !u64:
    ret try write(this, bytes)
..

# Returns a writer for this file.
# @complexity O(1).
# @throws invalidArgument when the file is closed or lacks write access
# @ownership The returned writer borrows the File, which must remain open.
# @example
#   output := try handle.writer()
File.writer() !w.Writer:
    if this.open == false || (this.openMode.bits & fopm.FLAG_WRITE) == 0:
        throw errors.invalidArgument("file not open in write mode")
    ..
    ret this.protoBorrow()
..

# Reads bytes from an open file handle.
# @complexity O(N) for byte count.
read(f File*, buff u8[], n u64) !u64:
    if f.open == false:
        throw errors.invalidArgument("read from closed file")
    ..
    ret try impl_file.read(f.handle, buff, n)
..

File.readRaw(buff u8[], n u64) !u64:
    ret try read(this, buff, n)
..

# Returns a reader for this file.
# @complexity O(1).
# @throws invalidArgument when the file is closed or lacks read access
# @ownership The returned reader borrows the File, which must remain open.
# @example
#   input := try handle.reader()
File.reader() !r.Reader:
    if this.open == false || (this.openMode.bits & fopm.FLAG_READ) == 0:
        throw errors.invalidArgument("file not open in read mode")
    ..
    ret this.protoBorrow()
..

# Advances the file pointer to the desired position.
# whence is 0 for start, 1 for current position, or 2 for end.
# @complexity O(1), excluding platform syscall cost
# @returns resulting absolute byte position
# @throws invalidArgument when the file is closed
# @example
#   position := try handle.seek(0, 0)
File.seek(offset i64, whence u8) !u64:
    if this.open == false:
        throw errors.invalidArgument("seek on closed file")
    ..
    ret try impl_file.seek(this.handle, offset, whence)
..

# Returns the file size in bytes without changing the current position.
# @complexity O(1), excluding platform syscall cost
# @throws invalidArgument when the file is closed
# @example
#   byteCount := try handle.count()
File.count() !u64:
    if this.open == false:
        throw errors.invalidArgument("count on closed file")
    ..
    position u64 = try impl_file.seek(this.handle, 0, 1)
    count u64, countErr error = impl_file.seek(this.handle, 0, 2)
    if countErr.nok():
        # Best effort restoration; preserve the original seek failure.
        impl_file.seek(this.handle, cast.utoi(position), 0)
        throw countErr
    ..
    try impl_file.seek(this.handle, cast.utoi(position), 0)
    ret count
..

runReadAt(task ReadTask*, signal abort.Signal) !$str:
    ctx.alloc = task.allocator
    try signal.check()
    if task.hasExternal: try task.external.check() ..
    result $str = try strings.alloc(task.count)
    onerror result.free()
    base := strings.toPtr(result)
    total u64 = 0
    loop total < task.count:
        try signal.check()
        if task.hasExternal: try task.external.check() ..
        amount := task.count - total
        if amount > 262144: amount = 262144 ..
        destination := cast.utop(cast.ptou(base) + total)
        view := slices.fromPtr(cast.reinterpret[u8](destination), amount)
        count := try impl_file.readAt(task.file.handle, view, amount, task.offset + total)
        total = total + count
        if count < amount:
            break
        ..
    ..
    unsafe: base[total] = 0 ..
    if strings.truncate(addrof result, total) == false:
        throw errors.failure("file read produced an invalid byte count")
    ..
    ret move result
..

# Starts an abortable positional read without changing the file cursor.
# The File must remain open until the returned Future is awaited.
File.readAsync(offset u64, count u64) !$future.Future[str]:
    if this.open == false || (this.openMode.bits & fopm.FLAG_READ) == 0:
        throw errors.invalidArgument("file not open in read mode")
    ..
    task := ReadTask(file=this, allocator=ctx.alloc, offset=offset, count=count, external=abort.Signal(state=none), hasExternal=false)
    ret try future.newAbort[str, ReadTask](ctx.exec, runReadAt, task)
..

# Starts a positional read observing both its Future and caller-owned signal.
File.readAsyncAbort(offset u64, count u64, signal abort.Signal) !$future.Future[str]:
    if this.open == false || (this.openMode.bits & fopm.FLAG_READ) == 0:
        throw errors.invalidArgument("file not open in read mode")
    ..
    task := ReadTask(file=this, allocator=ctx.alloc, offset=offset, count=count, external=signal, hasExternal=true)
    ret try future.newAbort[str, ReadTask](ctx.exec, runReadAt, task)
..

# Opens a file with the provided path and mode.
# @warning caller must close the file to avoid leaks.
# @complexity O(1) aside from path conversion and syscalls.
# @param path file path
# @param openMode desired open mode
# @returns open file handle
# @mustcall close
# @example
#   handle := try file.open("data.bin", file.mode().read())
pub open(path str, openMode fopm.OpenMode) !$File:
    a := ctx.alloc
    handle ptr = try impl_file.openFile(path, openMode)
    ret File(handle=handle, openMode=openMode, open=true)
..

# Returns an empty mode that can be configured through chainable methods.
# @complexity O(1)
# @example
#   openMode := file.mode().write().create().truncate()
pub mode() fopm.OpenMode:
    ret fopm.OpenMode(bits=0)
..
