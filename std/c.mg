mod c
# Target-dependent aliases for interoperating with C APIs and data layouts.

# Target-dependent C integer types. The compiler-known names are internal
# plumbing; consumers should import this module and use its public aliases.
pub alias char = @compiler_known_type("c.char")
# Signed C char type with target-defined width and representation.
pub alias signed_char = @compiler_known_type("c.signed_char")
# Unsigned C char type with target-defined width.
pub alias unsigned_char = @compiler_known_type("c.unsigned_char")

# Signed C short integer type.
pub alias short = @compiler_known_type("c.short")
# Unsigned C short integer type.
pub alias unsigned_short = @compiler_known_type("c.unsigned_short")
# Signed C int type.
pub alias int = @compiler_known_type("c.int")
# Unsigned C int type.
pub alias unsigned_int = @compiler_known_type("c.unsigned_int")
# Signed C long type; width varies by target ABI.
pub alias long = @compiler_known_type("c.long")
# Unsigned C long type; width varies by target ABI.
pub alias unsigned_long = @compiler_known_type("c.unsigned_long")
# Signed C long long type.
pub alias long_long = @compiler_known_type("c.long_long")
# Unsigned C long long type.
pub alias unsigned_long_long = @compiler_known_type("c.unsigned_long_long")

# Unsigned type used by C for object sizes and element counts.
pub alias size_t = @compiler_known_type("c.size_t")
# Signed type used by C for pointer differences.
pub alias ptrdiff_t = @compiler_known_type("c.ptrdiff_t")
# Signed integer type capable of storing a pointer value.
pub alias intptr_t = @compiler_known_type("c.intptr_t")
# Unsigned integer type capable of storing a pointer value.
pub alias uintptr_t = @compiler_known_type("c.uintptr_t")
# Target-defined C wide-character code-unit type.
pub alias wchar_t = @compiler_known_type("c.wchar_t")
