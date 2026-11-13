mod reader
# Type-erased byte input with convenience methods for exact and allocated reads.

use "std:context"   as context
use "std:allocator" as alc
use "std:slices"    as slices
use "std:strings"   as strings
use "std:errors"    as errors
use "std:cast"      as cast
use "std:future"    as future
use "std:abort"     as abort

# Reader interface for pulling bytes into strings or buffers.
# @complexity O(1) wrapper calls; underlying reader decides cost.
pub proto Reader(
    readRaw(buff u8[], nBytes u64) !u64
)

# Reads up to nBytes and returns a string containing the bytes read.
# @warning returned string is backed by allocator-owned memory.
# @complexity O(N) for nBytes.
# @param nBytes maximum bytes to read
# @returns string with read bytes
# @ownership Release the returned string with a.
# @example
#   chunk := try input.read(4096)
Reader.read(nBytes u64) !$str:
    a := ctx.alloc
    if nBytes == 0:
        ret try strings.alloc(0)
    ..
    result str = try strings.alloc(nBytes)
    onerror result.free()

    buffPtr u8* = strings.toPtr(result)
    buff u8[] = slices.fromPtr(buffPtr, nBytes)
    readCnt u64 = try this.readToBuff(buff, nBytes)
    # SAFETY: strings.alloc reserves the trailing terminator byte and readToBuff
    # returns no more than the supplied nBytes extent.
    unsafe:
        buffPtr[readCnt] = 0
    ..

    if strings.truncate(addrof result, readCnt) == false:
        throw errors.failure("reader produced an invalid byte count")
    ..
    ret move result
..

# Reads into the provided buffer up to nBytes bytes.
# @complexity O(N) for nBytes.
# @param buff destination buffer
# @param nBytes number of bytes to read
# @returns number of bytes read
# @throws invalidArgument when nBytes exceeds the destination length
# @example
#   count := try input.readToBuff(buffer, slices.count(buffer))
Reader.readToBuff(buff u8[], nBytes u64) !u64:
    if slices.count(buff) < nBytes:
        throw errors.invalidArgument("would overflow")
    ..
    readCnt u64 = try this.readRaw(buff, nBytes)
    if readCnt > nBytes:
        throw errors.failure("reader returned more bytes than requested")
    ..
    ret readCnt
..

ReaderReadTask(
    allocator alc.Allocator
    source Reader*
    count u64
    external abort.Signal
    hasExternal bool
)

runReadTask(task ReaderReadTask*, signal abort.Signal) !str:
    ctx.alloc = task.allocator
    try signal.check()
    if task.hasExternal:
        try task.external.check()
    ..
    ret try task.source.read(task.count)
..

Reader.readAsync(nBytes u64) !$future.Future[str]:
    task := ReaderReadTask(source=this, allocator=ctx.alloc, count=nBytes, external=abort.Signal(state=none), hasExternal=false)
    ret try future.newAbort[str, ReaderReadTask](ctx.exec, runReadTask, task)
..

# Asynchronously reads while also observing a caller-owned abort signal.
# The signal's Controller and Reader must remain alive through await.
Reader.readAsyncAbort(nBytes u64, signal abort.Signal) !$future.Future[str]:
    task := ReaderReadTask(source=this, allocator=ctx.alloc, count=nBytes, external=signal, hasExternal=true)
    ret try future.newAbort[str, ReaderReadTask](ctx.exec, runReadTask, task)
..
