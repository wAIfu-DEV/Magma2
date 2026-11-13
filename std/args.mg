mod args
# Allocation-free helpers for the argument slice supplied to main.

use "std:slices" as slices
use "std:errors" as errors
use "std:iterator" as iterator

pub Args(
    raw str[]
)

pub new(raw str[]) Args:
    ret Args(raw=raw)
..

Args.count() u64:
    count := slices.count(this.raw)
    if count == 0:
        ret 0
    ..
    ret count - 1
..

Args.executable() !str:
    if slices.count(this.raw) == 0:
        throw errors.outOfBounds("argument slice has no executable")
    ..
    ret this.raw[0]
..

Args.values() str[]:
    count := slices.count(this.raw)
    if count == 0:
        ret this.raw
    ..
    ret slices.fromPtr(addrof this.raw[1], count - 1)
..

Args.get(index u64) !str:
    values := this.values()
    if index >= slices.count(values):
        throw errors.outOfBounds("argument index is out of bounds")
    ..
    ret values[index]
..

iterHasData(impl Args*, index u64) bool:
    ret index < impl.count()
..

iterNext(impl Args*, index u64) !str:
    ret try impl.get(index)
..

Args.iterator() iterator.Iterator[str]:
    ret iterator.new[str](this, iterHasData, iterNext)
..
