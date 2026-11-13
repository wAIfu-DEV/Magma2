mod random
# Deterministic pseudo-random values and operating-system randomness.

use "std:slices" as slices

@platform("linux", "android")
use "std:linux/random_impl" as impl

@platform("windows")
use "std:win/random_impl" as impl

@platform("ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/random_impl" as impl

# Stateful deterministic pseudo-random number generator.
pub Random(
    state u64
)

# Stateless generator backed by the operating-system random source.
pub OsRandom(
    reserved u8
)

# Creates an operating-system-backed random generator.
# @complexity O(1)
# @example
#   rng := random.os()
pub os() OsRandom:
    ret OsRandom(reserved=0)
..

# Creates a generator from a seed; zero selects a fixed nonzero seed.
# Equal seeds produce equal sequences.
# @complexity O(1)
# @example
#   rng := random.new(42)
pub new(seed u64) Random:
    actualSeed := seed
    if actualSeed == 0:
        actualSeed = 11400714819323198485
    ..
    ret Random(state=actualSeed)
..

# Advances the generator and returns a value spanning the u64 range.
# @complexity O(1)
# @example
#   value := rng.next()
Random.next() u64:
    x := this.state
    x = x ^ (x >> 12)
    x = x ^ (x << 25)
    x = x ^ (x >> 27)
    this.state = x
    ret x * 2685821657736338717
..

# Returns a value in [0, bound), or zero when bound is zero.
# @complexity O(1)
# @warning Modulo reduction introduces bias unless bound divides the u64 range.
# @example
#   dieRoll := rng.below(6) + 1
Random.below(bound u64) u64:
    if bound == 0:
        ret 0
    ..
    ret this.next() % bound
..

# Returns a pseudo-random boolean with equal probability for both values.
# @complexity O(1)
# @example
#   heads := rng.bool()
Random.bool() bool:
    ret (this.next() & 1) == 1
..

# Returns owned cryptographically secure bytes from the operating system.
# @complexity O(N), where N is the slice length
# @ownership Release the result with slices.free.
# @throws failure when the operating-system random source fails
# @example
#   nonce := try random.bytes(16)
#   defer slices.free(nonce)
pub bytes(count u64) !$u8[]:
    result := try slices.alloc[u8](count)
    onerror slices.free(result)
    try bytesTo(result)
    ret move result
..

# Fills caller-provided storage with cryptographically secure bytes.
# @complexity O(N), where N is the slice length
# @throws failure when the operating-system random source fails
# @example
#   nonce := [16]u8
#   output u8[] = slices.fromPtr(slices.toPtr(nonce), 16)
#   try random.bytesTo(output)
pub bytesTo(output u8[]) !void:
    try impl.randomBytes(output)
..

# Returns a cryptographically secure random value spanning the u64 range.
# @complexity O(1), excluding the operating-system query
# @throws failure when the operating-system random source fails
# @example
#   value := try random.next()
pub next() !u64:
    value u64 = 0
    output u8[] = slices.fromPtr(addrof value, sizeof u64)
    try bytesTo(output)
    ret value
..

# Returns a cryptographically secure value in [0, bound), or zero when bound is zero.
# Rejection sampling avoids modulo bias.
# @complexity O(1) expected, excluding operating-system queries
# @throws failure when the operating-system random source fails
# @example
#   dieRoll := try random.below(6) + 1
pub below(bound u64) !u64:
    if bound == 0:
        ret 0
    ..
    threshold := (0 - bound) % bound
    loop true:
        value := try next()
        if value >= threshold:
            ret value % bound
        ..
    ..
..

# Returns a cryptographically secure random boolean.
# @complexity O(1), excluding the operating-system query
# @throws failure when the operating-system random source fails
# @example
#   heads := try random.bool()
pub bool() !bool:
    ret (try next() & 1) == 1
..

# Returns a cryptographically secure random value spanning the u64 range.
OsRandom.next() !u64:
    ret try next()
..

# Returns a cryptographically secure value in [0, bound), or zero when bound is zero.
OsRandom.below(bound u64) !u64:
    ret try below(bound)
..

# Returns a cryptographically secure random boolean.
OsRandom.bool() !bool:
    ret try bool()
..
