mod file_impl_win
# Windows file backend used by the portable file and I/O modules.


use "std:win/types" as win
use "std:utf8"      as utf8
use "std:allocator" as alc
use "std:slices"    as slices
use "std:strings"   as strings
use "std:cast"      as cast
use "std:errors"    as errors
use "std:writer"    as writer
use "std:reader"    as reader
use "std:file_op_mode" as fopm
use "std:llvm"      as ll

ext ext_win32_CreateFileW      CreateFileW(pathUtf16 win.LPCWSTR, accessMode win.DWORD, shareMode win.DWORD, securityAttributes win.LPVOID, createMode win.DWORD, flagsAndAttributes win.DWORD, templateFile win.HANDLE) win.HANDLE
ext ext_win32_CloseHandle      CloseHandle(handle win.HANDLE) win.BOOL
ext ext_win32_WriteFile        WriteFile(handle win.HANDLE, buffer win.LPCVOID, bytesToWrite win.DWORD, bytesWritten win.DWORD*, overlapped win.LPVOID) win.BOOL
ext ext_win32_ReadFile         ReadFile(handle win.HANDLE, buffer win.LPVOID, bytesToRead win.DWORD, bytesRead win.DWORD*, overlapped win.LPVOID) win.BOOL
ext ext_win32_GetStdHandle     GetStdHandle(handleNum win.DWORD) win.HANDLE
ext ext_win32_SetFilePointerEx SetFilePointerEx(handle win.HANDLE, distance win.LONGLONG, newPosition win.LONGLONG*, moveMethod win.DWORD) win.BOOL
ext ext_win32_GetLastError     GetLastError() win.DWORD

global cachedStdin ptr
global cachedStdout ptr
global cachedStderr ptr

standardHandleSlot(kind u32) ptr:
   if kind == 0 - 10: ret addrof cachedStdin ..
   if kind == 0 - 11: ret addrof cachedStdout ..
   ret addrof cachedStderr
..

loadCachedStandardHandle(kind u32) ptr:
   ret ll.atomicLoadAcquirePtr(standardHandleSlot(kind))
..

publishStandardHandle(kind u32, value ptr) void:
   ll.atomicStoreReleasePtr(standardHandleSlot(kind), value)
..

standardHandle(kind u32) ptr:
   value := loadCachedStandardHandle(kind)
   if value == none:
      value = ext_win32_GetStdHandle(kind)
      if value != none: publishStandardHandle(kind, value) ..
   ..
   ret value
..

# Magma globals are thread-local by default. These syscall output slots avoid
# repeated stack allocation without sharing state between threads.
gl_writeOnce_written u64
gl_readOnce_read u64

# Writes up to amount bytes once using Win32 WriteFile.
# O(1) per call.
writeOnce(handle ptr, next ptr, amount u32) !u64:
   # HACK: using global var for out ptr
   # in order to minimize stack allocations, allows extreme inlining
   # using a stack allocated var forces LLVM to generate it at call site too since
   # call to external function requires valid state without assumptions,
   # leading to guaranteed alloca instruction for each write call.
   ok win.BOOL = ext_win32_WriteFile(handle, next, amount, addrof gl_writeOnce_written, none)
   
   if ok == 0:
      throw errors.native(cast.u64to32(ext_win32_GetLastError()), "WriteFile failed")
   ..

   ret gl_writeOnce_written
..

# Writes a string to a Win32 file handle.
# O(N) for byte count.
# @param handle file handle
# @param bytes string to write
# @returns bytes written
pub write(handle ptr, bytes str) !u64:
   bound u64 = bytes.countBytes()

   if bound == 0:
      ret 0
   ..

   # happy path (short string)
   # should help optimize if size is known at comptime
   if bound <= 0xFFFFFFFF:
      ret try writeOnce(handle, strings.toPtr(bytes), cast.u64to32(bound))
   ..

   p u8* = strings.toPtr(bytes)
   total u64 = 0

   loop total < bound:
      toWrite u32 = 0
      if (bound - total) > 0xFFFFFFFF:
         toWrite = 0xFFFFFFFF
      else:
         toWrite = cast.u64to32(bound - total)
      ..

      if toWrite == 0:
         break
      ..

      next ptr = cast.utop(cast.ptou(p) + total)
      written u64 = try writeOnce(handle, next, toWrite)

      total = total + written
      # Note: might need EOF flag reset

      if written < cast.u32to64(toWrite):
         break
      ..
   ..
   ret total
..

# Reads up to amount bytes once using Win32 ReadFile.
# O(1) per call.
readOnce(handle ptr, next ptr, amount u32) !u64:

   # HACK: see writeOnce
   ok win.BOOL = ext_win32_ReadFile(handle, next, amount, addrof gl_readOnce_read, none)

   if ok == 0:
      throw errors.native(cast.u64to32(ext_win32_GetLastError()), "ReadFile failed")
   ..

   # Note: if read == 0 should set EOF flag
   # Future me: what the fuck are you talking about
   ret gl_readOnce_read
..

# Reads into a buffer from a Win32 file handle.
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
   # happy path (short string)
   # should help optimize if size is known at comptime
   if n <= 0xFFFFFFFF:
      ret try readOnce(handle, slices.toPtr(buff), cast.u64to32(n))
   ..
   ret try readOnce(handle, slices.toPtr(buff), 0xFFFFFFFF)
..

# Positional fallback for synchronous Windows handles. Callers must not mix
# this operation concurrently with cursor-based operations on the same File.
pub readAt(handle ptr, buff u8[], n u64, offset u64) !u64:
   previous := try seek(handle, 0, 1)
   try seek(handle, cast.utoi(offset), 0)
   count u64, readError error = read(handle, buff, n)
   restored u64, restoreError error = seek(handle, cast.utoi(previous), 0)
   if readError.nok(): throw readError ..
   if restoreError.nok(): throw restoreError ..
   ret count
..

# Returns a writer for the Win32 standard output handle.
# O(1).
Console impl writer.Writer(handle ptr, handleId u32)

Console.writeRaw(bytes str) !u64:
   if this.handle == none:
      this.handle = standardHandle(this.handleId)
   ..
   ret try write(this.handle, bytes)
..

gl_stdout := Console(handle=none, handleId=0xFFFFFFF5)
gl_stderr := Console(handle=none, handleId=0xFFFFFFF4)

pub stdout() writer.Writer:
   ret gl_stdout.protoBorrow()
..

# The interface is constant; only the OS handle cache is mutable. Magma globals
# are thread-local, so this preserves the existing per-thread behavior.
gl_constStdoutHandle ptr

writeConstStdout(impl ptr, bytes str) !u64:
   if gl_constStdoutHandle == none:
      gl_constStdoutHandle = standardHandle(-11)
   ..
   ret try write(gl_constStdoutHandle, bytes)
..

const gl_stdoutWriter := writer.ConstWriter(
   impl=none,
   fn_write=writeConstStdout,
)

pub stdoutConst() writer.ConstWriter*:
   ret addrof gl_stdoutWriter
..

# Returns a writer for the Win32 standard error handle.
# O(1).
pub stderr() writer.Writer:
   ret gl_stderr.protoBorrow()
..

Stdin impl reader.Reader(handle ptr)

Stdin.readRaw(bytes u8[], count u64) !u64:
   if this.handle == none:
      this.handle = standardHandle(-10)
   ..
   ret try read(this.handle, bytes, count)
..

gl_stdin := Stdin(handle=none)

# Returns a reader for the Win32 standard input handle.
# O(1).
pub stdin() reader.Reader:
   ret gl_stdin.protoBorrow()
..

# Closes a Win32 file handle.
# O(1).
pub closeFile(handle ptr) !void:
   if ext_win32_CloseHandle(handle) == 0:
      throw errors.native(cast.u64to32(ext_win32_GetLastError()), "CloseHandle failed")
   ..
..

# Opens a file using Win32 CreateFileW.
# O(1) aside from path conversion and syscalls.
# @param a allocator to use
# @param path UTF-8 path
# @param openMode desired open mode
# @returns handle to the opened file
pub openFile(path str, openMode fopm.OpenMode) !$ptr:
    a := ctx.alloc
   READ  u32 = 0x80000000
   WRITE u32 = 0x40000000
   APPEND u32 = 4

   OPEN_EXISTING u32 = 3
   CREATE_ALWAYS u32 = 2
   OPEN_ALWAYS u32 = 4
   TRUNCATE_EXISTING u32 = 5

   access_mode u32
   open_mode u32

   if (openMode.bits & fopm.FLAG_APPEND) != 0:
      access_mode = APPEND
      if (openMode.bits & fopm.FLAG_READ) != 0:
         access_mode = access_mode | READ
      ..
   elif (openMode.bits & fopm.FLAG_READ) != 0 && (openMode.bits & fopm.FLAG_WRITE) != 0:
      access_mode = READ | WRITE
   elif (openMode.bits & fopm.FLAG_READ) != 0:
      access_mode = READ
   elif (openMode.bits & fopm.FLAG_WRITE) != 0:
      access_mode = WRITE
   else:
      throw errors.invalidArgument("invalid open mode")
   ..

   if (openMode.bits & fopm.FLAG_CREATE) != 0 && (openMode.bits & fopm.FLAG_TRUNCATE) != 0:
      open_mode = CREATE_ALWAYS
   elif (openMode.bits & fopm.FLAG_CREATE) != 0:
      open_mode = OPEN_ALWAYS
   elif (openMode.bits & fopm.FLAG_TRUNCATE) != 0:
      open_mode = TRUNCATE_EXISTING
   else:
      open_mode = OPEN_EXISTING
   ..

   path_u16 u16[] = try utf8.utf8To16NT(path)
   path_ptr u16* = cast.reinterpret[u16](slices.toPtr(path_u16))

   defer a.free(path_ptr) # frees created utf16 string

   handle ptr = ext_win32_CreateFileW(path_ptr, access_mode, 0, none, open_mode, 0, none)

   # invalid handle
   if cast.ptou(handle) == cast.itou(-1):
      throw errors.native(cast.u64to32(ext_win32_GetLastError()), "CreateFileW failed")
   ..
   ret handle
..

pub seek(handle ptr, offset i64, whence u8) !u64:
   # Convert whence to Windows constants
   FILE_BEGIN   u32 = 0
   FILE_CURRENT u32 = 1
   FILE_END     u32 = 2
    
   moveMethod u32 = 0
   if whence == 0:
      moveMethod = FILE_BEGIN
   elif whence == 1:
      moveMethod = FILE_CURRENT
   elif whence == 2:
      moveMethod = FILE_END
   else:
      throw errors.invalidArgument("invalid whence")
   ..
    
   newPos i64 = 0
   if ext_win32_SetFilePointerEx(handle, offset, addrof newPos, moveMethod) == 0:
      throw errors.native(cast.u64to32(ext_win32_GetLastError()), "SetFilePointerEx failed")
   ..
   if newPos < 0:
      throw errors.failure("seek returned a negative position")
   ..
   ret cast.itou(newPos)
..
