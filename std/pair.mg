mod pair
# Small generic product types used when ordinary destructuring is unsuitable.

# Generic two-value product. Fields are intentionally explicit because ordinary
# value destructuring is reserved for throwing function results.
pub Pair[A, B](
    first $A
    second $B
)

# Constructs a pair from two values.
# @complexity O(1)
# @param first first component
# @param second second component
# @returns pair containing both components
# @example
#   entry := pair.new("answer", 42)
pub new[A, B](first $A, second $B) Pair[A, B]:
    ret Pair[A, B](first=move first, second=move second)
..
