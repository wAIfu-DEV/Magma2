mod builder
# Efficiently constructs owned strings from incrementally appended values.

use "std:allocator" as alc
use "std:strings" as strings
use "std:slices" as slices
use "std:memory" as mem
use "std:cast" as cast
use "std:errors" as errors
use "std:checked" as checked
use "std:writer" as writer

const FLAG_OWNED u8 = 1
const FLAG_BYTE u8 = 2

Segment(
    value str
    flags u8
)

# Accumulates borrowed and owned string segments before producing one owned string.
pub Builder impl writer.Writer(
    allocator alc.Allocator
    segments ptr
    count u64
    capacity u64
    totalBytes u64
)

# Creates an empty builder using a for segment storage and copied strings.
# @complexity O(1), excluding allocator cost
# @ownership Release with Builder.free.
# @example
#   output := try builder.new()
pub new() !$Builder:
    a := ctx.alloc
    ret try newWithCapacity(8)
..

# Creates an empty builder using a for segment storage and copied strings.
# Uses the provided chunkCapacity to set initial chunk capacity.
# This will allocate n chunks that will be filled before reallocation.  
# Note that appended string's sizes doesn't influence the count of allocations,
# only the amount of strings appended influence allocation count.
# @complexity O(1), excluding allocator cost
# @ownership Release with Builder.free.
# @example
#   output := try builder.newWithCapacity(8)
pub newWithCapacity(chunkCapacity u64) !$Builder:
    a := ctx.alloc
    if chunkCapacity == 0:
        throw errors.invalidArgument("builder capacity must be positive")
    ..
    ret Builder(
        allocator=a,
        segments=try a.allocT[Segment](chunkCapacity),
        count=0,
        capacity=chunkCapacity,
        totalBytes=0,
    )
..

Builder.ensureCapacity() !void:
    if this.count < this.capacity:
        ret
    ..
    newCapacity := try checked.uMul(this.capacity, 2)
    segmentPtr Segment* = cast.reinterpret[Segment](this.segments)
    newSegments Segment* = try this.allocator.reallocT[Segment](segmentPtr, newCapacity)
    this.segments = newSegments
    this.capacity = newCapacity
..

Builder.addBorrowed(s str) !void:
    byteCount u64 = s.countBytes()
    newTotal := try checked.uAdd(this.totalBytes, byteCount)
    try this.ensureCapacity()
    # SAFETY: ensureCapacity guarantees segments has capacity for count + 1.
    unsafe:
        segments Segment* = this.segments
        segment := Segment(value=s, flags=0)
        segments[this.count] = segment
    ..
    this.count = this.count + 1
    this.totalBytes = newTotal
..

Builder.addOwned(s $str) !void:
    onerror s.free()
    byteCount u64 = s.countBytes()
    newTotal := try checked.uAdd(this.totalBytes, byteCount)
    try this.ensureCapacity()
    # SAFETY: ensureCapacity guarantees an unoccupied slot at count; the flag
    # records that releaseCopies owns the transferred string in that slot.
    unsafe:
        segments Segment* = this.segments
        segment := Segment(value=move s, flags=FLAG_OWNED)
        segments[this.count] = segment
    ..
    this.count = this.count + 1
    this.totalBytes = newTotal
..

Builder.addByte(b u8) !void:
    newTotal := try checked.uAdd(this.totalBytes, 1)
    try this.ensureCapacity()
    # SAFETY: ensureCapacity reserves the slot, and FLAG_BYTE makes the ptr-sized
    # inline payload a byte value rather than an address to dereference.
    unsafe:
        segments Segment* = this.segments
        val ptr = none
        p u8* = cast.reinterpret[u8](addrof val)
        *p = b
        segment := Segment(value=strings.fromPtrNoCopy(val, 0), flags=FLAG_BYTE)
        segments[this.count] = segment
    ..
    this.count = this.count + 1
    this.totalBytes = newTotal
..

# Appends a borrowed segment without copying it.
# @complexity Amortized O(1)
# @ownership s must remain valid until build or reset completes.
# @example
#   try output.appendBorrowed("prefix: ")
Builder.appendBorrowed(s str) !void:
    try this.addBorrowed(s)
..

# Transfers an owned string into the builder.
# @complexity Amortized O(1)
# @ownership The builder releases s during reset or free.
# @example
#   try output.appendOwned(ownedText)
Builder.appendOwned(s $str) !void:
    try this.addOwned(move s)
..

# Copies and appends a string, making the segment independent of s.
# @complexity O(N), where N is the string byte length
# @example
#   try output.appendCopy(temporaryText)
Builder.appendCopy(s str) !void:
    byteCount := s.countBytes()
    if byteCount == 0:
        ret
    ..
    newTotal := try checked.uAdd(this.totalBytes, byteCount)
    # Reserve the segment first so allocation of the owned bytes is the final
    # fallible operation before committing the segment.
    try this.ensureCapacity()
    owned str = try strings.copy(s)
    # SAFETY: ensureCapacity reserves slot count and FLAG_OWNED records its
    # transferred string for exactly-once cleanup by releaseCopies.
    unsafe:
        segments Segment* = this.segments
        segment := Segment(value=move owned, flags=FLAG_OWNED)
        segments[this.count] = segment
    ..
    this.count = this.count + 1
    this.totalBytes = newTotal
..

# Writes bytes by copying them into an owned segment.
# Writer does not communicate the lifetime of its input, so retaining a
# borrowed segment here would allow the bytes to become invalid before build.
# @complexity O(N), where N is the string byte length
Builder.writeRaw(bytes str) !u64:
    try this.appendCopy(bytes)
    ret bytes.countBytes()
..

# Concatenates all segments into a newly allocated owned string.
# Building does not clear the builder or release copied segments.
# @complexity O(N), where N is the total output byte length
# @ownership Release the returned string with the builder's allocator.
# @example
#   text := try output.build()
Builder.build() !$str:
    if this.totalBytes == 0:
        ret try strings.alloc(0)
    ..
    result str = try strings.alloc(this.totalBytes)
    slc u8[] = slices.fromPtr(strings.toPtr(result), result.countBytes())

    try this.buildToBuff(slc)
    ret move result
..

Builder.buildToBuff(buff u8[]) !void:
    if buff.count() < this.byteCount():
        throw errors.wouldOverflow("buildToBuff would overflow buffer")
    ..

    out u8* = cast.reinterpret[u8](slices.toPtr(buff))
    offset u64 = 0
    i u64 = 0

    byteBuff := [2]u8
    byteBuff[1] = 0

    # SAFETY: segments contains count initialized entries, totalBytes is their
    # checked byte sum, and result has exactly totalBytes writable bytes.
    unsafe:
        segments Segment* = this.segments
        loop i < this.count:
            seg Segment = segments[i]
            s := seg.value

            if (seg.flags & FLAG_BYTE) != 0:
                p := strings.toPtr(s)
                byteBuff[0] = *(cast.reinterpret[u8](addrof p))
                s = strings.fromPtrNoCopy(slices.toPtr(byteBuff), 1)
            ..

            byteCount := s.countBytes()
            mem.copy(strings.toPtr(s), cast.utop(cast.ptou(out) + offset), byteCount)
            offset = offset + byteCount
            i = i + 1
        ..
    ..
..

# Returns the byte length of the string that build would produce.
# @complexity O(1)
Builder.byteCount() u64:
    ret this.totalBytes
..

# Reports whether no segments have been appended.
# @complexity O(1)
Builder.isEmpty() bool:
    ret this.count == 0
..

Builder.releaseCopies() void:
    # SAFETY: slots below count are initialized; FLAG_OWNED is the occupancy
    # bit for strings owned uniquely by this builder.
    unsafe:
        segments Segment* = this.segments
        for i u64 = 0 to this.count:
            if (segments[i].flags & FLAG_OWNED) != 0:
                segments[i].value.free()
            ..
        ..
    ..
..

# Releases copied and transferred segments while retaining segment capacity.
# @complexity O(S), where S is the number of segments
# @example
#   try output.reset()
Builder.reset() !void:
    this.releaseCopies()
    this.count = 0
    this.totalBytes = 0
..

# Releases all owned segments and the builder's segment storage.
# @complexity O(S), where S is the number of segments
# @example
#   output.free()
destr Builder.free() void:
    this.releaseCopies()
    this.allocator.free(this.segments)
    this.count = 0
    this.capacity = 0
    this.totalBytes = 0
..

destr Builder.buildFinal() !$str:
    defer this.free()
    ret try this.build()
..

Builder.writer() writer.Writer:
    ret this.protoBorrow()
..
