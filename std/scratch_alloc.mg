mod scratch_alloc
# Reusable free-list allocation within a fixed-size memory region.

use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:memory" as memory
use "std:slices" as slices
use "std:checked" as checked

const DEFAULT_CAPACITY u64 = 65536
const ALIGNMENT u64 = 16

Block(
    size u64
    free bool
)

# Fixed-capacity allocator that splits and coalesces blocks within its storage.
pub Scratch impl allocator.Allocator(
    backing allocator.Allocator*
    bytes u8*
    capacityValue u64
    ownsBytes bool
)

nextBlock(scratch Scratch*, block Block*) Block*:
    nextAddress := cast.ptou(block) + sizeof Block + block.size
    endAddress := cast.ptou(scratch.bytes) + scratch.capacityValue
    if nextAddress >= endAddress:
        ret none
    ..
    ret cast.reinterpret[Block](cast.utop(nextAddress))
..

scratchAlloc(raw ptr, byteCount u64) !u8*:
    scratch Scratch* = none
    # SAFETY: allocator() stores addrof its live Scratch as the vtable context.
    unsafe:
        scratch = raw
    ..
    if byteCount == 0:
        throw errors.invalidArgument("scratch allocation size must be greater than zero")
    ..
    required := try checked.alignUp(byteCount, ALIGNMENT)
    block Block* = cast.reinterpret[Block](scratch.bytes)
    loop block != none:
        if block.free && block.size >= required:
            remaining := block.size - required
            if remaining >= sizeof Block + ALIGNMENT:
                split Block* = cast.reinterpret[Block](cast.utop(cast.ptou(block) + sizeof Block + required))
                split.size = remaining - sizeof Block
                split.free = true
                block.size = required
            ..
            block.free = false
            ret cast.reinterpret[u8](cast.utop(cast.ptou(block) + sizeof Block))
        ..
        block = nextBlock(scratch, block)
    ..
    throw errors.outOfMemory("scratch capacity exhausted")
..

findBlock(scratch Scratch*, pointer u8*) Block*:
    block Block* = cast.reinterpret[Block](scratch.bytes)
    loop block != none:
        if cast.ptou(block) + sizeof Block == cast.ptou(pointer):
            ret block
        ..
        block = nextBlock(scratch, block)
    ..
    ret none
..

coalesce(scratch Scratch*) void:
    block Block* = cast.reinterpret[Block](scratch.bytes)
    loop block != none:
        next := nextBlock(scratch, block)
        if next != none && block.free && next.free:
            block.size = block.size + sizeof Block + next.size
        else:
            block = next
        ..
    ..
..

scratchFree(raw ptr, pointer u8*) void:
    if pointer == none:
        ret
    ..
    scratch Scratch* = none
    # SAFETY: allocator() stores addrof its live Scratch as the vtable context.
    unsafe:
        scratch = raw
    ..
    block := findBlock(scratch, pointer)
    if block == none || block.free:
        ret
    ..
    block.free = true
    coalesce(scratch)
..

scratchRealloc(raw ptr, pointer u8*, byteCount u64) !u8*:
    if pointer == none:
        ret try scratchAlloc(raw, byteCount)
    ..
    if byteCount == 0:
        throw errors.invalidArgument("scratch allocation size must be greater than zero")
    ..
    scratch Scratch* = none
    # SAFETY: allocator() stores addrof its live Scratch as the vtable context.
    unsafe:
        scratch = raw
    ..
    block := findBlock(scratch, pointer)
    if block == none || block.free:
        throw errors.invalidArgument("block does not belong to scratch allocator")
    ..
    required := try checked.alignUp(byteCount, ALIGNMENT)
    if required <= block.size:
        ret pointer
    ..
    next := nextBlock(scratch, block)
    if next != none && next.free && block.size + sizeof Block + next.size >= required:
        block.size = block.size + sizeof Block + next.size
        remaining := block.size - required
        if remaining >= sizeof Block + ALIGNMENT:
            split Block* = cast.reinterpret[Block](cast.utop(cast.ptou(block) + sizeof Block + required))
            split.size = remaining - sizeof Block
            split.free = true
            block.size = required
        ..
        ret pointer
    ..
    replacement := try scratchAlloc(raw, byteCount)
    memory.copy(pointer, replacement, block.size)
    scratchFree(raw, pointer)
    ret replacement
..

Scratch.alloc(byteCount u64) !$u8*:
    ret try scratchAlloc(this, byteCount)
..

Scratch.realloc(pointer ptr, byteCount u64) !$u8*:
    ret try scratchRealloc(this, cast.reinterpret[u8](pointer), byteCount)
..

Scratch.free(pointer ptr) void:
    scratchFree(this, cast.reinterpret[u8](pointer))
..

initialize(bytes u8*, capacity u64, ownsBytes bool) !Scratch:
    a := ctx.alloc
    if capacity < sizeof Block + ALIGNMENT:
        throw errors.invalidArgument("scratch capacity is too small")
    ..
    initial Block* = cast.reinterpret[Block](bytes)
    initial.size = capacity - sizeof Block
    initial.free = true
    backing allocator.Allocator* = none
    if ownsBytes:
        backing = try a.allocT[allocator.Allocator](1)
        unsafe:
            *backing = a
        ..
    ..
    ret Scratch(backing=backing, bytes=bytes, capacityValue=capacity, ownsBytes=ownsBytes)
..

# Creates owned scratch storage with the requested capacity.
pub new(capacity u64) !$Scratch:
    a := ctx.alloc
    if capacity < sizeof Block + ALIGNMENT:
        throw errors.invalidArgument("scratch capacity is too small")
    ..
    bytes := try a.alloc(capacity)
    onerror a.free(bytes)
    value Scratch = try initialize(bytes, capacity, true)
    ret value
..

# Creates owned scratch storage with the default 64 KiB capacity.
pub newDefault() !$Scratch:
    ret try new(DEFAULT_CAPACITY)
..

# Creates scratch storage over a caller-owned buffer.
pub fromBuffer(buffer u8[]) !Scratch:
    address := cast.ptou(slices.toPtr(buffer))
    padding := (ALIGNMENT - (address & (ALIGNMENT - 1))) & (ALIGNMENT - 1)
    if padding > buffer.count():
        throw errors.invalidArgument("scratch buffer is too small after alignment")
    ..
    ret try initialize(cast.reinterpret[u8](cast.utop(address + padding)), buffer.count() - padding, false)
..

# Returns a non-owning allocator view. Scratch must remain at a stable address.
Scratch.allocator() allocator.Allocator:
    ret this.protoBorrow()
..

# Releases every scratch allocation and restores one free block.
Scratch.reset() void:
    initial Block* = cast.reinterpret[Block](this.bytes)
    initial.size = this.capacityValue - sizeof Block
    initial.free = true
..

Scratch.capacity() u64:
    ret this.capacityValue
..

# Releases owned storage. Caller-provided storage is not freed.
destr Scratch.destroy() void:
    if this.ownsBytes && this.bytes != none:
        backing := this.backing
        backing.free(this.bytes)
        backing.free(backing)
    ..
    this.backing = none
    this.bytes = none
    this.capacityValue = 0
    this.ownsBytes = false
..
