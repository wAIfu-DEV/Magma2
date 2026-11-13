mod memory
# Low-level byte copying, movement, comparison, initialization, and swapping.
# @safety Callers must provide valid pointers spanning the requested byte count.

use "std:cast" as cast
use "std:llvm" as llvm_ir

# Copies n bytes from 'from' to 'to'.
# @warning prefer move() for possibly overlapping regions
# @complexity O(N) for n bytes.
# @param from source pointer
# @param to destination pointer
# @param n number of bytes to copy
# @safety Both ranges must be valid for n bytes and must not overlap.
# @example
#   memory.copy(source, destination, byteCount)
pub copy(source ptr, destination ptr, n u64) void:
    # will lower to @llvm.memcpy.p0.p0.i64

    # SAFETY: the API contract requires two valid n-byte non-overlapping ranges.
    unsafe:
        au u8* = source
        bu u8* = destination
        bounded au by n, bu by n:
            copyBytes(au, bu, n)
        ..
    ..
..

copyBytes(source u8* bounded n, destination u8* bounded n, n u64) void:
    for i u64 = 0 to n:
        destination[i] = source[i]
    ..
..

# Copies n bytes from possibly overlapping 'from' to 'to'.
# @complexity O(N) for n bytes.
# @param from source pointer
# @param to destination pointer
# @param n number of bytes to copy
# @safety Both ranges must be valid for n bytes.
# @example
#   memory.move(source, destination, byteCount)
pub move(source ptr, destination ptr, n u64) void:
    reg0 u64 = cast.ptou(source)
    reg1 u64 = cast.ptou(destination)

    # Subtraction is used instead of reg0 + n so an address-range check cannot
    # wrap at U64_MAX.
    if reg1 > reg0 && (reg1 - reg0) < n:
        # SAFETY: the API contract provides valid n-byte ranges; reverse copy
        # preserves overlapping regions.
        unsafe:
            au u8* = source
            bu u8* = destination
            bounded au by n, bu by n:
                moveBytesBackward(au, bu, n)
            ..
        ..
    else:
        # safe to copy left-to-right
        copy(source, destination, n)
    ..
..

moveBytesBackward(source u8* bounded n, destination u8* bounded n, n u64) void:
    bound u64 = 0 - 1 # U64_MAX
    i u64 = n - 1
    loop i != bound: # stops after 0
        bounded i < n:
            destination[i] = source[i]
        ..
        i = i - 1
    ..
..

# Swaps n bytes between non-overlapping x and y.
# @warning Using with overlapping x and y may cause loss of data
# @complexity O(N) for n bytes, zero allocation.
# @param x first pointer
# @param y second pointer
# @param n number of bytes to swap
# @safety Both ranges must be valid for n bytes and must not overlap.
# @example
#   memory.swap(left, right, sizeof Value)
pub swap(x ptr, y ptr, n u64) void:
    # SAFETY: the API contract requires two valid n-byte non-overlapping ranges.
    unsafe:
        ax u8* = x
        ay u8* = y
        bounded ax by n, ay by n:
            swapBytes(ax, ay, n)
        ..
    ..
..

swapBytes(x u8* bounded n, y u8* bounded n, n u64) void:
    for i u64 = 0 to n:
        tmp u8 = x[i]
        x[i] = y[i]
        y[i] = tmp
    ..
..

# Compares two byte ranges and returns true if all n bytes match.
# @complexity O(N) for n bytes.
# @param a first pointer
# @param b second pointer
# @param n number of bytes to compare
# @returns true if all bytes are equal
# @safety Both ranges must be readable for n bytes.
# @example
#   same := memory.compare(left, right, byteCount)
pub compare(a ptr, b ptr, n u64) bool:
    # fails to lower to llvm intrinsics, however code is tight so it should be good,
    # though it could use some optimization with variable length chunking.

    # SAFETY: the API contract requires two readable n-byte ranges.
    unsafe:
        au u8* = a
        bu u8* = b
        bounded au by n, bu by n:
            ret compareBytes(au, bu, n)
        ..
    ..
..

compareBytes(a u8* bounded n, b u8* bounded n, n u64) bool:
    for i u64 = 0 to n:
        if a[i] != b[i]:
            ret false
        ..
    ..
    ret true
..

# Reports whether every byte in a readable range is zero.
# @complexity O(N) for n bytes.
# @param in start of the readable range
# @param n number of bytes to inspect
# @safety in must reference a readable range of at least n bytes.
pub isZero(in ptr, n u64) bool:
    unsafe:
        bytes u8* = in
        bounded bytes by n:
            ret isZeroBytes(bytes, n)
        ..
    ..
..

isZeroBytes(bytes u8* bounded n, n u64) bool:
    for i u64 = 0 to n:
        if bytes[i] != 0:
            ret false
        ..
    ..
    ret true
..

# Fills n bytes starting at in with the provided byte value.
# @complexity O(N) for n bytes.
# @param in destination pointer
# @param n number of bytes to write
# @param with byte value to set
# @safety in must reference a writable range of at least n bytes.
# @example
#   memory.set(destination, byteCount, 255)
pub set(in ptr, n u64, with u8) void:
    # will lower to @llvm.memset.p0i8.i64

    # SAFETY: the API contract requires a writable n-byte range.
    unsafe:
        inu u8* = in
        bounded inu by n:
            setBytes(inu, n, with)
        ..
    ..
..

setBytes(in u8* bounded n, n u64, with u8) void:
    for i u64 = 0 to n:
        in[i] = with
    ..
..

# Zeros n bytes starting at in.
# @complexity O(N) for n bytes.
# @param in destination pointer
# @param n number of bytes to zero
# @safety in must reference a writable range of at least n bytes.
# @example
#   memory.zero(destination, byteCount)
pub zero(in ptr, n u64) void:
    set(in, n, 0)
..

# Returns a zero initialized value of type T 
# @complexity O(1)
# @returns T with every field initialized to its zero value
# @example
#   empty := memory.zeroValue[Header]()
pub zeroValue[T]() T:
    x T
    ret x
..
