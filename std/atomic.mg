mod atomic
use "std:llvm" as ll
# Sequentially consistent atomic numeric values for cross-thread coordination.
# @warning Do not copy an atomic value after publishing it to other threads.

# Atomic operations use sequential consistency, matching the default ordering
# of C++ atomics. Do not copy an atomic value after publishing it to threads.

# Atomically accessed unsigned 8-bit value.
# @warning Initialize with newU8 before sharing its address between threads.
pub U8(
    value u8
)

# Atomically accessed unsigned 32-bit value.
# @warning Initialize with newU32 before sharing its address between threads.
pub U32(
    value u32
)

# Atomically accessed unsigned 64-bit value with sequential, acquire/release,
# and relaxed operations for counters and synchronization state.
pub U64(
    value u64
)

# Atomically accessed signed 64-bit value.
pub I64(
    value i64
)

# Atomically accessed f64 value supporting load, store, and exchange.
pub F64(
    value f64
)

# Creates an atomic u8 with the supplied initial value.
# @complexity O(1)
# @example
#   flag := atomic.newU8(0)
pub newU8(value u8) U8:
    ret U8(value=value)
..

# Creates an atomic u32 with the supplied initial value.
# @complexity O(1)
# @example
#   state := atomic.newU32(0)
pub newU32(value u32) U32:
    ret U32(value=value)
..

# Creates an atomic u64 with the supplied initial value.
# @complexity O(1)
# @example
#   requests := atomic.newU64(0)
pub newU64(value u64) U64:
    ret U64(value=value)
..

# Creates an atomic i64 with the supplied initial value.
# @complexity O(1)
# @example
#   balance := atomic.newI64(0)
pub newI64(value i64) I64:
    ret I64(value=value)
..

# Creates an atomic f64 with the supplied initial value.
# @complexity O(1)
# @example
#   latest := atomic.newF64(0.0)
pub newF64(value f64) F64:
    ret F64(value=value)
..

# Replaces the value with sequential consistency.
# @complexity O(1)
# @example
#   flag.store(1)
U8.store(value u8) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreSequentialU8(this, value)
..

# Reads the value with sequential consistency.
# @complexity O(1)
# @example
#   ready := flag.load() != 0
U8.load() u8:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicLoadSequentialU8(this)
..

# Atomically replaces the value and returns its previous value.
# @complexity O(1)
# @example
#   wasSet := flag.exchange(1) != 0
U8.exchange(value u8) u8:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicExchangeSequentialU8(this, value)
..

# Reads with acquire ordering, observing writes published before a matching release.
# @complexity O(1)
# @example
#   ready := flag.loadAcquire() != 0
U8.loadAcquire() u8:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicLoadAcquireU8(this)
..

# Stores with release ordering, publishing prior writes to acquiring threads.
# @complexity O(1)
# @example
#   flag.storeRelease(1)
U8.storeRelease(value u8) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreReleaseU8(this, value)
..

# Atomically adds value and returns the value from before the addition.
# @complexity O(1)
# @warning Arithmetic wraps at the u8 boundary.
# @example
#   previous := counter.fetchAdd(1)
U8.fetchAdd(value u8) u8:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchAddSequentialU8(this, value)
..

# Atomically subtracts value and returns the value from before subtraction.
# @complexity O(1)
# @warning Arithmetic wraps at the u8 boundary.
# @example
#   previous := counter.fetchSub(1)
U8.fetchSub(value u8) u8:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchSubSequentialU8(this, value)
..

# Replaces the value with sequential consistency.
# @complexity O(1)
# @example
#   state.store(2)
U32.store(value u32) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreSequentialU32(this, value)
..

# Reads the value with sequential consistency.
# @complexity O(1)
# @example
#   current := state.load()
U32.load() u32:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicLoadSequentialU32(this)
..

# Atomically replaces the value and returns its previous value.
# @complexity O(1)
# @example
#   previous := state.exchange(2)
U32.exchange(value u32) u32:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicExchangeSequentialU32(this, value)
..

# Reads with acquire ordering, observing writes published before a matching release.
# @complexity O(1)
# @example
#   current := state.loadAcquire()
U32.loadAcquire() u32:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicLoadAcquireU32(this)
..

# Stores with release ordering, publishing prior writes to acquiring threads.
# @complexity O(1)
# @example
#   state.storeRelease(1)
U32.storeRelease(value u32) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreReleaseU32(this, value)
..

# Atomically adds value with sequential consistency and returns the previous value.
# @complexity O(1)
# @warning Arithmetic wraps at the u32 boundary.
# @example
#   ticket := counter.fetchAdd(1)
U32.fetchAdd(value u32) u32:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchAddSequentialU32(this, value)
..

# Adds with release ordering and returns the previous value, publishing prior writes.
# @complexity O(1)
# @warning Arithmetic wraps at the u32 boundary.
# @example
#   previous := counter.fetchAddRelease(1)
U32.fetchAddRelease(value u32) u32:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchAddReleaseU32(this, value)
..

# Atomically subtracts value with sequential consistency and returns the previous value.
# @complexity O(1)
# @warning Arithmetic wraps at the u32 boundary.
# @example
#   previous := counter.fetchSub(1)
U32.fetchSub(value u32) u32:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchSubSequentialU32(this, value)
..

# Subtracts with acquire-release ordering and returns the previous value.
# @complexity O(1)
# @warning Arithmetic wraps at the u32 boundary.
# @example
#   wasLast := references.fetchSubAcqRel(1) == 1
U32.fetchSubAcqRel(value u32) u32:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchSubAcqRelU32(this, value)
..

# Replaces the value with sequential consistency.
# @complexity O(1)
# @example
#   counter.store(0)
U64.store(value u64) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreSequentialU64(this, value)
..

# Reads the value with sequential consistency.
# @complexity O(1)
# @example
#   total := counter.load()
U64.load() u64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicLoadSequentialU64(this)
..

# Atomically replaces the value and returns its previous value.
# @complexity O(1)
# @example
#   batch := counter.exchange(0)
U64.exchange(value u64) u64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicExchangeSequentialU64(this, value)
..

# Replaces expected with desired when the current value equals expected and
# returns the value observed before the operation.
U64.compareExchange(expected u64, desired u64) u64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicCompareExchangeSequentialU64(this, expected, desired)
..

# Reads atomically without synchronizing other memory accesses.
# @complexity O(1)
# @warning Use only when atomicity is needed but cross-variable ordering is not.
# @example
#   approximate := counter.loadRelaxed()
U64.loadRelaxed() u64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicLoadRelaxedU64(this)
..

# Reads with acquire ordering, observing writes published before a matching release.
# @complexity O(1)
# @example
#   published := state.loadAcquire()
U64.loadAcquire() u64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicLoadAcquireU64(this)
..

# Stores atomically without publishing preceding memory accesses.
# @complexity O(1)
# @warning Use only when cross-variable ordering is not required.
# @example
#   counter.storeRelaxed(0)
U64.storeRelaxed(value u64) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreRelaxedU64(this, value)
..

# Stores with release ordering, publishing prior writes to acquiring threads.
# @complexity O(1)
# @example
#   state.storeRelease(1)
U64.storeRelease(value u64) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreReleaseU64(this, value)
..

# Atomically adds value with sequential consistency and returns the previous value.
# @complexity O(1)
# @warning Arithmetic wraps at the u64 boundary.
# @example
#   id := counter.fetchAdd(1)
U64.fetchAdd(value u64) u64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchAddSequentialU64(this, value)
..

# Atomically adds without synchronizing other memory and returns the previous value.
# @complexity O(1)
# @warning Arithmetic wraps; relaxed ordering cannot publish other data.
# @example
#   previous := metrics.fetchAddRelaxed(1)
U64.fetchAddRelaxed(value u64) u64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchAddRelaxedU64(this, value)
..

# Atomically subtracts value with sequential consistency and returns the previous value.
# @complexity O(1)
# @warning Arithmetic wraps at the u64 boundary.
# @example
#   previous := counter.fetchSub(1)
U64.fetchSub(value u64) u64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchSubSequentialU64(this, value)
..

# Replaces the signed value with sequential consistency.
# @complexity O(1)
# @example
#   balance.store(0)
I64.store(value i64) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreSequentialI64(this, value)
..

# Reads the signed value with sequential consistency.
# @complexity O(1)
# @example
#   current := balance.load()
I64.load() i64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicLoadSequentialI64(this)
..

# Atomically replaces the signed value and returns its previous value.
# @complexity O(1)
# @example
#   previous := balance.exchange(0)
I64.exchange(value i64) i64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicExchangeSequentialI64(this, value)
..

# Atomically adds value and returns the value from before the addition.
# @complexity O(1)
# @warning Signed overflow wraps according to the underlying integer operation.
# @example
#   previous := balance.fetchAdd(delta)
I64.fetchAdd(value i64) i64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchAddSequentialI64(this, value)
..

# Atomically subtracts value and returns the value from before subtraction.
# @complexity O(1)
# @warning Signed overflow wraps according to the underlying integer operation.
# @example
#   previous := balance.fetchSub(cost)
I64.fetchSub(value i64) i64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.atomicFetchSubSequentialI64(this, value)
..

# Atomically replaces the floating-point value with sequential consistency.
# @complexity O(1)
# @example
#   latest.store(measurement)
F64.store(value f64) void:
    # SAFETY: this audited implementation injects the required low-level IR.
    ll.atomicStoreSequentialU64(this, ll.f64ToBits(value))
..

# Reads the floating-point value with sequential consistency.
# @complexity O(1)
# @example
#   measurement := latest.load()
F64.load() f64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.f64FromBits(ll.atomicLoadSequentialU64(this))
..

# Atomically replaces the floating-point value and returns its previous value.
# This exchanges the exact IEEE-754 bit pattern without numeric conversion.
# @complexity O(1)
# @example
#   previous := latest.exchange(measurement)
F64.exchange(value f64) f64:
    # SAFETY: this audited implementation injects the required low-level IR.
    ret ll.f64FromBits(ll.atomicExchangeSequentialU64(this, ll.f64ToBits(value)))
..
