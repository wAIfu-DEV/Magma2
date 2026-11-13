mod arena_alloc
# Fast bump allocation for groups of values that share a lifetime.

use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:memory" as memory
use "std:slices" as slices
use "std:checked" as checked

const DEFAULT_CAPACITY u64 = 65536
const ALIGNMENT u64 = 16
const HEADER_SIZE u64 = 16

Header(
    size u64
    previousOffset u64
)

# Owned or borrowed arena storage. Individual frees are no-ops; reset releases
# every arena allocation at once.
pub Arena impl allocator.Allocator(
    backing allocator.Allocator*
    bytes u8*
    capacityValue u64
    offset u64
    ownsBytes bool
)

arenaAlloc(raw ptr, byteCount u64) !u8*:
    arena Arena*
    # SAFETY: allocator callbacks receive the Arena address installed by allocator().
    unsafe:
        arena = raw
    ..
    if byteCount == 0:
        throw errors.invalidArgument("arena allocation size must be greater than zero")
    ..
    headerOffset := try checked.alignUp(arena.offset, ALIGNMENT)
    dataOffset := try checked.uAdd(headerOffset, HEADER_SIZE)
    if byteCount > arena.capacityValue || dataOffset > arena.capacityValue - byteCount:
        throw errors.outOfMemory("arena capacity exhausted")
    ..
    header Header* = cast.reinterpret[Header](cast.utop(cast.ptou(arena.bytes) + headerOffset))
    header.size = byteCount
    header.previousOffset = arena.offset
    arena.offset = dataOffset + byteCount
    ret cast.reinterpret[u8](cast.utop(cast.ptou(arena.bytes) + dataOffset))
..

arenaRealloc(raw ptr, block u8*, byteCount u64) !u8*:
    arena Arena*
    # SAFETY: allocator callbacks receive the Arena address installed by allocator().
    unsafe:
        arena = raw
    ..
    if block == none:
        ret try arenaAlloc(raw, byteCount)
    ..
    if byteCount == 0:
        throw errors.invalidArgument("arena allocation size must be greater than zero")
    ..
    blockAddress := cast.ptou(block)
    baseAddress := cast.ptou(arena.bytes)
    if blockAddress < baseAddress + HEADER_SIZE || blockAddress > baseAddress + arena.capacityValue:
        throw errors.invalidArgument("block does not belong to arena")
    ..
    header Header* = cast.reinterpret[Header](cast.utop(blockAddress - HEADER_SIZE))
    blockEnd := blockAddress - baseAddress + header.size
    if blockEnd == arena.offset:
        dataOffset := blockAddress - baseAddress
        if byteCount > arena.capacityValue || dataOffset > arena.capacityValue - byteCount:
            throw errors.outOfMemory("arena capacity exhausted")
        ..
        header.size = byteCount
        arena.offset = dataOffset + byteCount
        ret block
    ..
    replacement := try arenaAlloc(raw, byteCount)
    copyCount := header.size
    if byteCount < copyCount:
        copyCount = byteCount
    ..
    memory.copy(block, replacement, copyCount)
    ret replacement
..

arenaFree(raw ptr, block u8*) void:
    ret
..

Arena.alloc(byteCount u64) !$u8*:
    ret try arenaAlloc(this, byteCount)
..

Arena.realloc(block ptr, byteCount u64) !$u8*:
    ret try arenaRealloc(this, cast.reinterpret[u8](block), byteCount)
..

Arena.free(block ptr) void:
    arenaFree(this, cast.reinterpret[u8](block))
..

# Creates an arena with owned storage of capacity bytes.
pub new(capacity u64) !$Arena:
    if capacity < HEADER_SIZE + ALIGNMENT:
        throw errors.invalidArgument("arena capacity is too small")
    ..
    a := ctx.alloc
    bytes := try a.alloc(capacity)
    onerror a.free(bytes)
    backing := try a.allocT[allocator.Allocator](1)
    unsafe:
        *backing = a
    ..
    ret Arena(backing=backing, bytes=bytes, capacityValue=capacity, offset=0, ownsBytes=true)
..

# Creates an arena with the default 64 KiB capacity.
pub newDefault() !$Arena:
    a := ctx.alloc
    ret try new(DEFAULT_CAPACITY)
..

# Creates an arena over caller-owned storage. The storage must outlive the arena.
pub fromBuffer(buffer u8[]) !Arena:
    address := cast.ptou(slices.toPtr(buffer))
    padding := (ALIGNMENT - (address & (ALIGNMENT - 1))) & (ALIGNMENT - 1)
    if padding > buffer.count() || buffer.count() - padding < HEADER_SIZE + ALIGNMENT:
        throw errors.invalidArgument("arena buffer is too small after alignment")
    ..
    ret Arena(
        backing=none,
        bytes=cast.reinterpret[u8](cast.utop(address + padding)),
        capacityValue=buffer.count() - padding,
        offset=0,
        ownsBytes=false,
    )
..

# Returns a non-owning allocator view. The arena must remain at a stable address.
Arena.allocator() allocator.Allocator:
    ret this.protoBorrow()
..

# Releases all allocations without modifying their bytes.
Arena.reset() void:
    this.offset = 0
..

Arena.used() u64:
    ret this.offset
..

Arena.capacity() u64:
    ret this.capacityValue
..

# Releases owned arena storage. Borrowed storage is left untouched.
destr Arena.destroy() void:
    if this.ownsBytes && this.bytes != none:
        backing := this.backing
        backing.free(this.bytes)
        backing.free(backing)
    ..
    this.backing = none
    this.bytes = none
    this.capacityValue = 0
    this.offset = 0
    this.ownsBytes = false
..
