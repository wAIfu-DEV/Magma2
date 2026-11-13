mod file_impl_unix
# Unix file backend used by the portable file and I/O modules.


use "std:c" as c
use "std:allocator" as alc
use "std:slices"    as slices
use "std:strings"   as strings
use "std:cast"      as cast
use "std:errors"    as errors
use "std:writer"    as writer
use "std:reader"    as reader
use "std:file_op_mode" as fopm

ext ext_unix_open  open(path u8*, flags c.int, mode c.int) c.int
ext ext_unix_close close(fd c.int) c.int
ext ext_unix_write write(fd c.int, buf ptr, count u64) i64
ext ext_unix_read  read(fd c.int, buf ptr, count u64) i64
ext ext_unix_pread pread(fd c.int, buf ptr, count u64, offset i64) i64
ext ext_unix_lseek lseek(fd c.int, offset i64, whence c.int) i64

# Magma globals are thread-local by default. These syscall result slots avoid
# repeated stack allocation without sharing state between threads.
gl_writeOnce_written i64
gl_readOnce_read i64

# Casts a pointer to a file descriptor integer.
# O(1).
ptoi32(x ptr) i32:
    ret cast.i64to32(cast.utoi(cast.ptou(x)))
..

# Casts file descriptor integer to a pointer.
# O(1).
i32top(x i32) ptr:
    ret cast.utop(cast.itou(cast.i32to64(x)))
..

# Writes up to amount bytes once using unix write.
# O(1) per call.
writeOnce(fd i32, next ptr, amount u64) !u64:
   gl_writeOnce_written = ext_unix_write(fd, next, amount)
   
   if gl_writeOnce_written < 0:
      throw errors.failure("write failed")
   ..
   ret cast.itou(gl_writeOnce_written)
..

# Writes a string to a unix file handle.
# O(N) for byte count.
# @param handle file handle
# @param bytes string to write
# @returns bytes written
pub write(handle ptr, bytes str) !u64:
    fd i32 = ptoi32(handle)
    bound u64 = bytes.countBytes()

    if bound == 0:
        ret 0
    ..

    p ptr
    # SAFETY: p is traversed only up to bytes.countBytes().
    unsafe:
        p = strings.toPtr(bytes)
    ..
    total u64 = 0

    loop total < bound:
        toWrite u64 = bound - total

        next ptr = cast.utop(cast.ptou(p) + total)
        written u64 = try writeOnce(fd, next, toWrite)

        total = total + written

        if written == 0:
            break
        ..
    ..
    ret total
..

# Reads up to amount bytes once using unix read.
# O(1) per call.
readOnce(fd i32, next ptr, amount u64) !u64:
   gl_readOnce_read = ext_unix_read(fd, next, amount)

   if gl_readOnce_read < 0:
      throw errors.failure("read failed")
   ..

   ret cast.itou(gl_readOnce_read)
..

# Reads into a buffer from a unix file handle.
# O(N) for byte count.
# @param handle file handle
# @param buff destination buffer
# @param n max bytes to read
# @returns bytes read
pub read(handle ptr, buff u8[], n u64) !u64:
   if slices.count(buff) < n:
      throw errors.invalidArgument("read would overflow buffer")
   ..
   if n == 0:
      ret 0
   ..
   ret try readOnce(ptoi32(handle), slices.toPtr(buff), n)
..

# Positional read that does not modify the shared file cursor.
pub readAt(handle ptr, buff u8[], n u64, offset u64) !u64:
   if slices.count(buff) < n:
      throw errors.invalidArgument("read would overflow buffer")
   ..
   if n == 0: ret 0 ..
   result i64 = ext_unix_pread(ptoi32(handle), slices.toPtr(buff), n, cast.utoi(offset))
   if result < 0:
      throw errors.failure("positional read failed")
   ..
   ret cast.itou(result)
..

# Returns a writer for standard output.
# O(1).
Console impl writer.Writer(fd u64)

Console.writeRaw(bytes str) !u64:
    ret try write(cast.utop(this.fd), bytes)
..

gl_stdout := Console(fd=1)
gl_stderr := Console(fd=2)

pub stdout() writer.Writer:
    ret gl_stdout.protoBorrow()
..

# Constant-interface variant used by std:io. Keeping the callback in a
# constant aggregate lets LLVM turn Writer.write calls into direct calls.
writeConstStdout(impl ptr, bytes str) !u64:
    ret try write(cast.utop(1), bytes)
..

const gl_stdoutWriter := writer.ConstWriter(
    impl=none,
    fn_write=writeConstStdout,
)

pub stdoutConst() writer.ConstWriter*:
    ret addrof gl_stdoutWriter
..

# Returns a writer for standard error.
# O(1).
pub stderr() writer.Writer:
    ret gl_stderr.protoBorrow()
..

Stdin impl reader.Reader(handle ptr)

Stdin.readRaw(bytes u8[], count u64) !u64:
    ret try read(this.handle, bytes, count)
..

gl_stdin := Stdin(handle=none)

# Returns a reader for standard input.
# O(1).
pub stdin() reader.Reader:
    ret gl_stdin.protoBorrow()
..

# Closes a unix file handle.
# O(1).
pub closeFile(handle ptr) !void:
   fd i32 = ptoi32(handle)
   if ext_unix_close(fd) != 0:
      throw errors.failure("close failed")
   ..
..

# Opens a file using unix open.
# O(1) aside from path conversion and syscalls.
# @param a allocator to use
# @param path UTF-8 path
# @param openMode desired open mode
# @returns handle to the opened file
pub openFile(path str, openMode fopm.OpenMode) !$ptr:
    a := ctx.alloc
    O_RDONLY i32 = 0
    O_WRONLY i32 = 1
    O_RDWR   i32 = 2
    O_CREAT  i32 = 64
    O_TRUNC  i32 = 512
    O_APPEND i32 = 1024

    flags i32 = 0
    mode i32 = 438  # 0666 in octal

    if (openMode.bits & fopm.FLAG_READ) != 0 && (openMode.bits & fopm.FLAG_WRITE) == 0:
        flags = O_RDONLY
    elif (openMode.bits & fopm.FLAG_WRITE) != 0 && (openMode.bits & fopm.FLAG_READ) == 0:
        flags = O_WRONLY
    elif (openMode.bits & fopm.FLAG_READ) != 0 && (openMode.bits & fopm.FLAG_WRITE) != 0:
        flags = O_RDWR
    else:
        throw errors.invalidArgument("invalid open mode")
    ..

    if (openMode.bits & fopm.FLAG_CREATE) != 0:
        flags = flags | O_CREAT
    ..
    if (openMode.bits & fopm.FLAG_TRUNCATE) != 0:
        flags = flags | O_TRUNC
    ..
    if (openMode.bits & fopm.FLAG_APPEND) != 0:
        flags = flags | O_APPEND
    ..

    path_cstr u8* = strings.toCstrNoCopy(path)
    fd i32 = ext_unix_open(path_cstr, flags, mode)

    if fd < 0:
        throw errors.failure("open failure")
    ..
    ret i32top(fd)
..

# Moves a unix file descriptor's file offset.
# O(1).
# @param handle file handle
# @param offset signed offset relative to whence
# @param whence 0 for start, 1 for current position, 2 for end
# @returns the resulting absolute file position
pub seek(handle ptr, offset i64, whence u8) !u64:
    SEEK_SET i32 = 0
    SEEK_CUR i32 = 1
    SEEK_END i32 = 2

    origin i32 = 0
    if whence == 0:
        origin = SEEK_SET
    elif whence == 1:
        origin = SEEK_CUR
    elif whence == 2:
        origin = SEEK_END
    else:
        throw errors.invalidArgument("invalid whence")
    ..

    position i64 = ext_unix_lseek(ptoi32(handle), offset, origin)
    if position < 0:
        throw errors.failure("seek failed")
    ..

    ret cast.itou(position)
..
