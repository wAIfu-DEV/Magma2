mod stable_list
# Append-only lists whose elements never move when the list grows.

use "std:allocator" as alc
use "std:checked" as checked
use "std:errors" as errors
use "std:list" as ls
use "std:memory" as mem

const PAGE_SIZE u64 = 256

# Append-only owning sequence backed by separately allocated fixed-size pages.
# The page directory may grow, but the elements in allocated pages never move.
# This type is not thread-safe; callers must synchronize concurrent access.
pub StableList[T](
    allocator alc.Allocator
    pages ls.List[T*]
    length u64
    cleanup fn($T) void
)

# Creates an empty stable list with an optional element cleanup callback.
# @ownership The returned list owns all pages and must be freed before its allocator.
pub new[T](a alc.Allocator, cleanup fn($T) void) !$StableList[T]:
    ret StableList[T](
        allocator=a,
        pages=try ls.new[T*](a, none),
        length=0,
        cleanup=cleanup,
    )
..

# Returns the number of appended elements.
StableList[T].count() u64:
    ret this.length
..

# Appends a value and returns its stable index.
# @ownership Consumes value.
# @complexity O(1) amortized; allocates a page every PAGE_SIZE elements.
StableList[T].push(value $T) !u64:
    newLength := try checked.uAdd(this.length, 1)
    if this.length % PAGE_SIZE == 0:
        pageBytes := try checked.byteCount[T](PAGE_SIZE)
        page := try this.allocator.allocT[T](PAGE_SIZE)
        onerror this.allocator.free(page)
        mem.zero(page, pageBytes)
        try this.pages.pushRight(move page)
    ..

    pageIndex := this.length / PAGE_SIZE
    offset := this.length % PAGE_SIZE
    page := try this.pages.get(pageIndex)
    unsafe:
        page[offset] = move value
    ..

    index := this.length
    this.length = newLength
    ret index
..

# Returns a mutable pointer to an element without moving it.
# @warning The pointer remains valid until this StableList is freed. The list
#          must not be concurrently freed or have the same element mutated.
# @throws outOfBounds when index has not been appended.
StableList[T].get(index u64) !T*:
    if index >= this.length:
        throw errors.outOfBounds("stable list index is out of bounds")
    ..

    page := try this.pages.get(index / PAGE_SIZE)
    offset := index % PAGE_SIZE
    unsafe:
        ret addrof page[offset]
    ..
..

# Releases all elements and pages. Element pointers become invalid.
destr StableList[T].free() void:
    unsafe:
        pages := this.pages.view()
        if this.cleanup != none:
            for pageIndex u64 = 0 to pages.count():
                page := pages[pageIndex]
                start := pageIndex * PAGE_SIZE
                remaining := this.length - start
                used := remaining
                if used > PAGE_SIZE:
                    used = PAGE_SIZE
                ..
                for offset u64 = 0 to used:
                    value $T = page[offset]
                    page[offset] = mem.zeroValue[T]()
                    this.cleanup(move value)
                ..
                this.allocator.free(page)
            ..
        else:
            for pageIndex u64 = 0 to pages.count():
                page := pages[pageIndex]
                this.allocator.free(page)
            ..
        ..
        this.pages.free()
        this.length = 0
    ..
..
