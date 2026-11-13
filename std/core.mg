mod core
# Intrinsic types and methods imported implicitly by every Magma program.

use "std:allocator" as alc
use "std:llvm" as low

# Capacity used by the allocation-free error trace arena.
const ERROR_TRACE_SLOTS u64 = @compiler_known("ERROR_TRACE_SLOTS")

# Canonical backing layouts for compiler-known values. Double-underscore
# fields are implementation details hidden from normal tooling suggestions.
pub str(
    __data u8*
    __byteCount u64
    __allocatorImpl ptr
    __allocatorVtable ptr
)

pub error(
    __message u8*
    __code u32
    __traceSlot u16
    __messageLength u16
)

pub slice(
    __data ptr
    __count u64
)

# Error propagation metadata is stored in Magma-owned bounded storage. The
# compiler passes pointers to immutable sites when it records a failing edge.
pub ErrorTraceSite(
    functionData u8*
    functionLength u64
    fileData u8*
    fileLength u64
    line u32
    column u32
)

ErrorTraceNode(
    lock u8
    sequence u32
    parent u64
    site ptr
)

ErrorTraceSnapshot(
    site ptr
    parent u16
    truncated bool
)

global errorTraceCursor u64
global errorTraceNodes := [ERROR_TRACE_SLOTS]ErrorTraceNode

pub noctx errorTracePush(value error, site ptr) error:
    ticket := low.atomicFetchAddRelaxedU64(addrof errorTraceCursor, 1)
    slot := ticket % ERROR_TRACE_SLOTS
    bounded slot < errorTraceNodes.count():
        node ErrorTraceNode* = addrof errorTraceNodes[slot]
        loop low.atomicCompareExchangeAcqRelU8(addrof node.lock, 0, 1) != 0:
            low.pause()
        ..
        low.atomicFetchAddSequentialU32(addrof node.sequence, 1)
        low.atomicStoreSequentialU64(addrof node.parent, low.zeroExtendU16ToU64(value.__traceSlot))
        low.atomicStoreReleasePtr(addrof node.site, site)
        low.atomicFetchAddSequentialU32(addrof node.sequence, 1)
        low.atomicStoreReleaseU8(addrof node.lock, 0)
        value.__traceSlot = low.truncateU64ToU16(slot + 1)
        ret value
    ..
    ret value
..

noctx errorTraceLoad(handle u16) ErrorTraceSnapshot:
    if handle == 0:
        ret ErrorTraceSnapshot(site=none, parent=0, truncated=false)
    ..
    slot := low.zeroExtendU16ToU64(handle) - 1
    bounded slot < errorTraceNodes.count():
        node ErrorTraceNode* = addrof errorTraceNodes[slot]
        before := low.atomicLoadAcquireU32(addrof node.sequence)
        if before % 2 != 0:
            ret ErrorTraceSnapshot(site=none, parent=0, truncated=true)
        ..
        parent := low.atomicLoadSequentialU64(addrof node.parent)
        site := low.atomicLoadAcquirePtr(addrof node.site)
        after := low.atomicLoadAcquireU32(addrof node.sequence)
        if after != before:
            ret ErrorTraceSnapshot(site=none, parent=0, truncated=true)
        ..
        ret ErrorTraceSnapshot(site=site, parent=low.truncateU64ToU16(parent), truncated=false)
    ..
    ret ErrorTraceSnapshot(site=none, parent=0, truncated=true)
..

pub noctx error.traceHandle() u64:
    ret low.zeroExtendU16ToU64(this.__traceSlot)
..

pub noctx u64.errorTraceStatus() u32:
    cursor u64 = *this
    if (cursor & 0x100000000) != 0:
        ret 2
    ..
    if low.truncateU64ToU16(cursor) == 0:
        ret 1
    ..
    ret 0
..

pub noctx u64.errorTraceNext() u64:
    cursor u64 = *this
    snapshot := errorTraceLoad(low.truncateU64ToU16(cursor))
    count := (cursor >> 16) & 0xffff
    nextCount := count + 1
    if snapshot.truncated || (nextCount >= ERROR_TRACE_SLOTS && snapshot.parent != 0):
        ret 0x100000000
    ..
    ret (nextCount << 16) | low.zeroExtendU16ToU64(snapshot.parent)
..

noctx errorTraceSite(cursor u64) ErrorTraceSite*:
    snapshot := errorTraceLoad(low.truncateU64ToU16(cursor))
    if snapshot.site == none:
        ret none
    ..
    ret low.reinterpret[ErrorTraceSite](snapshot.site)
..

pub noctx u64.errorTraceFunction() str:
    cursor u64 = *this
    site := errorTraceSite(cursor)
    if site == none:
        ret str(__data=none, __byteCount=0, __allocatorImpl=none, __allocatorVtable=none)
    ..
    ret str(__data=site.functionData, __byteCount=site.functionLength, __allocatorImpl=none, __allocatorVtable=none)
..

pub noctx u64.errorTraceFile() str:
    cursor u64 = *this
    site := errorTraceSite(cursor)
    if site == none:
        ret str(__data=none, __byteCount=0, __allocatorImpl=none, __allocatorVtable=none)
    ..
    ret str(__data=site.fileData, __byteCount=site.fileLength, __allocatorImpl=none, __allocatorVtable=none)
..

pub noctx u64.errorTraceLine() u32:
    cursor u64 = *this
    site := errorTraceSite(cursor)
    if site == none:
        ret 0
    ..
    ret site.line
..

pub noctx u64.errorTraceColumn() u32:
    cursor u64 = *this
    site := errorTraceSite(cursor)
    if site == none:
        ret 0
    ..
    ret site.column
..

# Returns the number of elements in a slice.
# @complexity O(1)
# @example
#   length := values.count()
noctx slice.count() u64:
    ret this.__count
..

# Canonical error predicates. Besides being convenient, these are the only
# predicates used by ownership flow refinement for destructured throwing calls.
# @complexity O(1)
# @example
#   if resultError.ok():
error.ok() bool:
    ret this.__code == 0
..

# Reports whether an error represents failure.
# @complexity O(1)
# @example
#   if resultError.nok():
error.nok() bool:
    ret this.__code != 0
..

# Returns the error code of an error.
# A code of 0 indicates a successful operation.
# @complexity O(1).
# @returns error code
# @example
#   category := failure.code()
noctx error.code() u32:
    ret this.__code
..

# Returns the message from an error. Error construction retains at most 65,535
# message bytes.
# @complexity O(1).
# @returns error message
# @example
#   detail := failure.message()
error.message() str:
    ret str(__data=this.__message, __byteCount=this.__messageLength, __allocatorImpl=none, __allocatorVtable=none)
..

# Releases the backing allocation of an owned string through its embedded
# allocator. Borrowed strings, literals, and the zero string have a null
# allocator vtable and are no-ops.
# @complexity O(1), excluding allocator cost
# @example
#   owned.free()
destr str.free() void:
    a := alc.fromEmbedded(addrof this.__allocatorImpl)
    if this.__data == none || a.isNull():
        ret
    ..
    a.free(this.__data)
..

# Returns size in bytes of string, for UTF8 strings codepoint (UTF8 character) count may be
# different from byte size.
# @complexity O(1) regardless of size.
# @param s input string
# @returns size in bytes of string
# @example
#   byteCount := myStr.countBytes()
str.countBytes() u64:
    ret this.__byteCount
..

# Compares two strings byte-for-byte. String equality operators lower to this
# core method, keeping the language operation independent of runtime symbols.
# @complexity O(N)
str.compare(other str) bool:
    if this.__byteCount != other.__byteCount:
        ret false
    ..
    leftData u8* = this.__data
    rightData u8* = other.__data
    size := this.__byteCount
    bounded leftData by size, rightData by size:
        for i := 0 to size:
            if leftData[i] != rightData[i]:
                ret false
            ..
        ..
    ..
    ret true
..
