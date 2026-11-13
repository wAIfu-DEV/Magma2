mod llvm
# Audited wrappers around commonly useful LLVM IR operations.
#
# This module is intentionally low level.  It makes inline LLVM available to
# ordinary Magma code without making every caller embed target IR.  Operations
# which access memory retain the same validity and alignment requirements as
# their LLVM counterparts.

# Reinterprets a raw pointer as a pointer to T.
# @safety The pointer must be suitably aligned and valid before dereferencing.
pub noctx reinterpret[T](value ptr) T*:
    unsafe:
        ret @llvm("reinterpret", value, T*)
    ..
..

# Returns a pointer advanced by a signed byte offset.
# @warning Pointer arithmetic does not validate that the result remains in an allocation.
pub noctx offset(pointer ptr, bytes i64) ptr:
    unsafe:
        ret @llvm("offset", pointer, bytes, ptr)
    ..
..

# Converts a pointer to its target-sized address representation.
pub noctx ptrToInt(value ptr) u64:
    unsafe:
        ret @llvm("ptrtoint", value, u64)
    ..
..

# Converts an address representation to a raw pointer.
# @safety The result must designate valid storage before it is accessed.
pub noctx intToPtr(value u64) ptr:
    unsafe:
        ret @llvm("inttoptr", value, ptr)
    ..
..

# Loads T from pointer.
# @safety pointer must be aligned and readable for sizeof T bytes.
pub noctx load[T](pointer ptr) T:
    unsafe:
        typed T* = pointer
        ret *typed
    ..
..

# Stores T at pointer.
# @safety pointer must be aligned and writable for sizeof T bytes.
pub noctx store[T](pointer ptr, value T) void:
    unsafe:
        typed T* = pointer
        *typed = value
    ..
..

# Constructs borrowed aggregate views without allocating. These helpers keep
# the aggregate representation in Magma; neither backend parses LLVM fragments.
pub noctx stringFromPtr(pointer ptr, byteCount u64) str:
    unsafe:
        data u8* = pointer
        value str
        value.__data = data
        value.__byteCount = byteCount
        ret value
    ..
..

pub noctx stringData(value str) ptr:
    ret value.__data
..

pub noctx stringByteCount(value str) u64:
    ret value.__byteCount
..

pub noctx sliceFromPtr[T](pointer ptr, count u64) T[]:
    ret slice(__data=pointer, __count=count)
..

pub noctx sliceData[T](value T[]) ptr:
    ret value.__data
..

pub noctx sliceCount[T](value T[]) u64:
    ret value.__count
..

# Volatile primitive loads and stores. Volatile prevents elimination and
# merging, but does not provide inter-thread atomicity.
pub noctx loadVolatileU8(pointer ptr) u8:
    unsafe:
        ret @llvm("load_volatile", pointer, 1, u8)
    ..
..

pub noctx storeVolatileU8(pointer ptr, value u8) void:
    unsafe:
        @llvm("store_volatile", pointer, value, 1, void)
    ..
..

pub noctx loadVolatileU32(pointer ptr) u32:
    unsafe:
        ret @llvm("load_volatile", pointer, 4, u32)
    ..
..

pub noctx storeVolatileU32(pointer ptr, value u32) void:
    unsafe:
        @llvm("store_volatile", pointer, value, 4, void)
    ..
..

pub noctx loadVolatileU64(pointer ptr) u64:
    unsafe:
        ret @llvm("load_volatile", pointer, 8, u64)
    ..
..

pub noctx storeVolatileU64(pointer ptr, value u64) void:
    unsafe:
        @llvm("store_volatile", pointer, value, 8, void)
    ..
..

# Raw atomic operations used by synchronization and platform modules. These
# operate on caller-owned storage rather than requiring an atomic wrapper type.
# @safety pointer must be naturally aligned and remain valid for the operation.
pub noctx atomicLoadAcquireU8(pointer ptr) u8:
    unsafe:
        ret @llvm("atomic_load", pointer, "acquire", 1, u8)
    ..
..

pub noctx atomicLoadAcquireU32(pointer ptr) u32:
    unsafe:
        ret @llvm("atomic_load", pointer, "acquire", 4, u32)
    ..
..

pub noctx atomicLoadAcquireU64(pointer ptr) u64:
    unsafe:
        ret @llvm("atomic_load", pointer, "acquire", 8, u64)
    ..
..

pub noctx atomicLoadAcquirePtr(pointer ptr) ptr:
    unsafe:
        ret @llvm("atomic_load", pointer, "acquire", 8, ptr)
    ..
..

pub noctx atomicLoadRelaxedU32(pointer ptr) u32:
    unsafe:
        ret @llvm("atomic_load", pointer, "monotonic", 4, u32)
    ..
..

pub noctx atomicLoadRelaxedU64(pointer ptr) u64:
    unsafe:
        ret @llvm("atomic_load", pointer, "monotonic", 8, u64)
    ..
..

pub noctx atomicLoadSequentialU8(pointer ptr) u8:
    unsafe:
        ret @llvm("atomic_load", pointer, "seq_cst", 1, u8)
    ..
..

pub noctx atomicLoadSequentialU32(pointer ptr) u32:
    unsafe:
        ret @llvm("atomic_load", pointer, "seq_cst", 4, u32)
    ..
..

pub noctx atomicLoadSequentialU64(pointer ptr) u64:
    unsafe:
        ret @llvm("atomic_load", pointer, "seq_cst", 8, u64)
    ..
..

pub noctx atomicLoadSequentialI64(pointer ptr) i64:
    unsafe:
        ret @llvm("atomic_load", pointer, "seq_cst", 8, i64)
    ..
..

pub noctx atomicStoreReleaseU8(pointer ptr, value u8) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "release", 1, void)
    ..
..

pub noctx atomicStoreReleaseU32(pointer ptr, value u32) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "release", 4, void)
    ..
..

pub noctx atomicStoreReleaseU64(pointer ptr, value u64) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "release", 8, void)
    ..
..

pub noctx atomicStoreReleasePtr(pointer ptr, value ptr) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "release", 8, void)
    ..
..

pub noctx atomicStoreRelaxedU64(pointer ptr, value u64) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "monotonic", 8, void)
    ..
..

pub noctx atomicStoreSequentialU8(pointer ptr, value u8) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "seq_cst", 1, void)
    ..
..

pub noctx atomicStoreSequentialU32(pointer ptr, value u32) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "seq_cst", 4, void)
    ..
..

pub noctx atomicStoreSequentialU64(pointer ptr, value u64) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "seq_cst", 8, void)
    ..
..

pub noctx atomicStoreSequentialI64(pointer ptr, value i64) void:
    unsafe:
        @llvm("atomic_store", pointer, value, "seq_cst", 8, void)
    ..
..

pub noctx atomicExchangeSequentialU8(pointer ptr, value u8) u8:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "xchg", "seq_cst", 1, u8)
    ..
..

pub noctx atomicExchangeSequentialU32(pointer ptr, value u32) u32:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "xchg", "seq_cst", 4, u32)
    ..
..

pub noctx atomicExchangeSequentialU64(pointer ptr, value u64) u64:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "xchg", "seq_cst", 8, u64)
    ..
..

pub noctx atomicExchangeSequentialI64(pointer ptr, value i64) i64:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "xchg", "seq_cst", 8, i64)
    ..
..

pub noctx atomicFetchAddRelaxedU64(pointer ptr, value u64) u64:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "add", "monotonic", 8, u64)
    ..
..

pub noctx atomicFetchAddAcqRelU64(pointer ptr, value u64) u64:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "add", "acq_rel", 8, u64)
    ..
..

pub noctx atomicFetchAddReleaseU32(pointer ptr, value u32) u32:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "add", "release", 4, u32)
    ..
..

pub noctx atomicFetchAddSequentialU8(pointer ptr, value u8) u8:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "add", "seq_cst", 1, u8)
    ..
..

pub noctx atomicFetchAddSequentialU32(pointer ptr, value u32) u32:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "add", "seq_cst", 4, u32)
    ..
..

pub noctx atomicFetchAddSequentialU64(pointer ptr, value u64) u64:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "add", "seq_cst", 8, u64)
    ..
..

pub noctx atomicFetchAddSequentialI64(pointer ptr, value i64) i64:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "add", "seq_cst", 8, i64)
    ..
..

pub noctx atomicFetchSubAcqRelU32(pointer ptr, value u32) u32:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "sub", "acq_rel", 4, u32)
    ..
..

pub noctx atomicFetchSubSequentialU8(pointer ptr, value u8) u8:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "sub", "seq_cst", 1, u8)
    ..
..

pub noctx atomicFetchSubSequentialU32(pointer ptr, value u32) u32:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "sub", "seq_cst", 4, u32)
    ..
..

pub noctx atomicFetchSubSequentialU64(pointer ptr, value u64) u64:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "sub", "seq_cst", 8, u64)
    ..
..

pub noctx atomicFetchSubSequentialI64(pointer ptr, value i64) i64:
    unsafe:
        ret @llvm("atomic_rmw", pointer, value, "sub", "seq_cst", 8, i64)
    ..
..

# Returns the observed old value. Equality with expected indicates success.
pub noctx atomicCompareExchangeAcquireU32(pointer ptr, expected u32, desired u32) u32:
    unsafe:
        ret @llvm("cmpxchg_old", pointer, expected, desired, "acquire", "monotonic", 4, u32)
    ..
..

pub noctx atomicCompareExchangeAcqRelU8(pointer ptr, expected u8, desired u8) u8:
    unsafe:
        ret @llvm("cmpxchg_old", pointer, expected, desired, "acq_rel", "acquire", 1, u8)
    ..
..

pub noctx atomicCompareExchangeSequentialU64(pointer ptr, expected u64, desired u64) u64:
    unsafe:
        ret @llvm("cmpxchg_old", pointer, expected, desired, "seq_cst", "seq_cst", 8, u64)
    ..
..

# Emits the x86 processor-pause hint with a memory clobber.
@platform("x86_64", "i386", "i486", "i586", "i686")
pub noctx pause() void:
    unsafe:
        @llvm("asm_sideeffect", "pause", void)
    ..
..

# Emits the ARM processor-yield hint with a memory clobber.
@platform("aarch64", "arm", "thumb")
pub noctx pause() void:
    unsafe:
        @llvm("asm_sideeffect", "yield", void)
    ..
..

# Preserves the spin-loop side effect on targets for which the standard library
# does not have a universally available architectural pause instruction.
@platform("wasm32", "wasm64", "riscv32", "riscv64", "ppc64", "ppc64le", "s390x")
pub noctx pause() void:
    unsafe:
        @llvm("sideeffect", void)
    ..
..

# Same-width bit reinterpretations.
pub noctx f64ToBits(value f64) u64:
    unsafe:
        ret @llvm("bitcast", value, u64)
    ..
..

pub noctx f64FromBits(value u64) f64:
    unsafe:
        ret @llvm("bitcast", value, f64)
    ..
..

pub noctx f32ToBits(value f32) u32:
    unsafe:
        ret @llvm("bitcast", value, u32)
    ..
..

pub noctx f32FromBits(value u32) f32:
    unsafe:
        ret @llvm("bitcast", value, f32)
    ..
..

# Numeric conversions corresponding to the inline IR used by std:cast.
pub noctx signExtendI8ToI64(value i8) i64:
    unsafe:
        ret @llvm("sext", value, i64)
    ..
..

pub noctx signExtendI16ToI64(value i16) i64:
    unsafe:
        ret @llvm("sext", value, i64)
    ..
..

pub noctx signExtendI32ToI64(value i32) i64:
    unsafe:
        ret @llvm("sext", value, i64)
    ..
..

pub noctx signExtendI64ToI128(value i64) i128:
    unsafe:
        ret @llvm("sext", value, i128)
    ..
..

pub noctx zeroExtendU8ToU64(value u8) u64:
    unsafe:
        ret @llvm("zext", value, u64)
    ..
..

pub noctx zeroExtendU16ToU64(value u16) u64:
    unsafe:
        ret @llvm("zext", value, u64)
    ..
..

pub noctx zeroExtendU32ToU64(value u32) u64:
    unsafe:
        ret @llvm("zext", value, u64)
    ..
..

pub noctx zeroExtendU64ToU128(value u64) u128:
    unsafe:
        ret @llvm("zext", value, u128)
    ..
..

pub noctx truncateI64ToI8(value i64) i8:
    unsafe:
        ret @llvm("trunc", value, i8)
    ..
..

pub noctx truncateI64ToI16(value i64) i16:
    unsafe:
        ret @llvm("trunc", value, i16)
    ..
..

pub noctx truncateI64ToI32(value i64) i32:
    unsafe:
        ret @llvm("trunc", value, i32)
    ..
..

pub noctx truncateI128ToI64(value i128) i64:
    unsafe:
        ret @llvm("trunc", value, i64)
    ..
..

pub noctx truncateU64ToU8(value u64) u8:
    unsafe:
        ret @llvm("trunc", value, u8)
    ..
..

pub noctx truncateU64ToU16(value u64) u16:
    unsafe:
        ret @llvm("trunc", value, u16)
    ..
..

pub noctx truncateU64ToU32(value u64) u32:
    unsafe:
        ret @llvm("trunc", value, u32)
    ..
..

pub noctx truncateU128ToU64(value u128) u64:
    unsafe:
        ret @llvm("trunc", value, u64)
    ..
..

pub noctx signedToF64(value i64) f64:
    unsafe:
        ret @llvm("sitofp", value, f64)
    ..
..

pub noctx unsignedToF64(value u64) f64:
    unsafe:
        ret @llvm("uitofp", value, f64)
    ..
..

pub noctx f64ToSigned(value f64) i64:
    unsafe:
        ret @llvm("fptosi", value, i64)
    ..
..

pub noctx f64ToUnsigned(value f64) u64:
    unsafe:
        ret @llvm("fptoui", value, u64)
    ..
..

pub noctx signedToUnsignedBits(value i64) u64:
    unsafe:
        ret @llvm("reinterpret", value, u64)
    ..
..

pub noctx unsignedToSignedBits(value u64) i64:
    unsafe:
        ret @llvm("reinterpret", value, i64)

    ..
..

pub noctx unsigned32ToSignedBits(value u32) i32:
    unsafe:
        ret @llvm("reinterpret", value, i32)
    ..
..

pub noctx unsigned128ToSignedBits(value u128) i128:
    unsafe:
        ret @llvm("reinterpret", value, i128)
    ..
..

pub noctx signed128ToUnsignedBits(value i128) u128:
    unsafe:
        ret @llvm("reinterpret", value, u128)
    ..
..

pub noctx byteSwap16(value u16) u16:
    unsafe:
        ret @llvm("bswap", value, u16)
    ..
..

pub noctx byteSwap32(value u32) u32:
    unsafe:
        ret @llvm("bswap", value, u32)

    ..
..

pub noctx byteSwap64(value u64) u64:
    unsafe:
        ret @llvm("bswap", value, u64)

    ..
..

pub noctx reverseBits8(value u8) u8:
    unsafe:
        ret @llvm("bitreverse", value, u8)

    ..
..

pub noctx reverseBits16(value u16) u16:
    unsafe:
        ret @llvm("bitreverse", value, u16)

    ..
..

pub noctx reverseBits32(value u32) u32:
    unsafe:
        ret @llvm("bitreverse", value, u32)

    ..
..

pub noctx reverseBits64(value u64) u64:
    unsafe:
        ret @llvm("bitreverse", value, u64)
    ..
..

pub noctx populationCount8(value u8) u8:
    unsafe:
        ret @llvm("ctpop", value, u8)
    ..
..

pub noctx populationCount16(value u16) u16:
    unsafe:
        ret @llvm("ctpop", value, u16)
    ..
..

pub noctx populationCount32(value u32) u32:
    unsafe:
        ret @llvm("ctpop", value, u32)
    ..
..

pub noctx populationCount64(value u64) u64:
    unsafe:
        ret @llvm("ctpop", value, u64)
    ..
..

# The zero inputs produce their full bit width rather than poison.
pub noctx leadingZeros32(value u32) u32:
    unsafe:
        ret @llvm("ctlz", value, u32)
    ..
..

pub noctx leadingZeros64(value u64) u64:
    unsafe:
        ret @llvm("ctlz", value, u64)
    ..
..

pub noctx trailingZeros32(value u32) u32:
    unsafe:
        ret @llvm("cttz", value, u32)

    ..
..

pub noctx trailingZeros64(value u64) u64:
    unsafe:
        ret @llvm("cttz", value, u64)
    ..
..

# Optimization hint that preserves the boolean value.
pub noctx expect(value bool, expected bool) bool:
    unsafe:
        ret @llvm("expect", value, expected, bool)
    ..
..

# Tells LLVM that condition is always true. Passing false is undefined behavior.
# @safety condition must be true whenever control reaches this call.
pub noctx assume(condition bool) void:
    unsafe:
        @llvm("assume", condition, void)
    ..
..

# Emits a sequentially consistent memory fence.
pub noctx fenceSequentiallyConsistent() void:
    unsafe:
        @llvm("fence", "seq_cst", void)
    ..
..

# Terminates execution with the target's trap instruction.
pub noctx trap() void:
    unsafe:
        @llvm("trap", void)
    ..
..
