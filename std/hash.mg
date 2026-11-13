mod hash
# Stable non-cryptographic hashing for byte slices and strings.
# @warning Do not use these hashes for passwords or cryptographic integrity.

use "std:strings" as strings
use "std:slices" as slices

# Computes the 64-bit FNV-1a hash of a byte slice.
# @complexity O(N)
# @param in bytes to hash
# @returns deterministic hash value
# @warning This hash is not suitable for cryptographic integrity or secrets.
# @example
#   value := hash.bytes(data)
pub bytes(in u8[]) u64:
    h u64 = 14695981039346656037
    for i u64 = 0 to slices.count(in):
        h = h ^ in[i]
        h = h * 1099511628211
    ..
    ret h
..

# Computes the 64-bit FNV-1a hash of a string's UTF-8 bytes.
# @complexity O(N)
# @param in string to hash
# @returns deterministic hash value
# @example
#   value := hash.string("magma")
pub string(in str) u64:
    data u8[] = slices.fromPtr(strings.toPtr(in), in.countBytes())
    ret bytes(data)
..
