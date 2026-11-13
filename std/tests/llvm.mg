mod main

use "std:llvm" as ll
use "std:errors" as errors

pub main() !void:
    word u64 = 42
    raw ptr = addrof word
    if ll.load[u64](raw) != 42 || ll.ptrToInt(ll.intToPtr(ll.ptrToInt(raw))) != ll.ptrToInt(raw):
        throw errors.failure("llvm pointer wrappers failed")
    ..
    ll.store[u64](raw, 99)
    typed u64* = ll.reinterpret[u64](ll.offset(raw, 0))
    if word != 99 || *typed != 99:
        throw errors.failure("llvm generic store failed")
    ..
    text := "llvm"
    rawText := ll.stringFromPtr(ll.stringData(text), ll.stringByteCount(text))
    view u64[] = ll.sliceFromPtr[u64](raw, 1)
    if rawText != text || ll.sliceData[u64](view) != raw || ll.sliceCount[u64](view) != 1:
        throw errors.failure("llvm aggregate wrappers failed")
    ..
    volatileByte u8 = 1
    volatileBytePointer ptr = addrof volatileByte
    ll.storeVolatileU8(volatileBytePointer, 2)
    volatileValue u32 = 7
    volatilePointer ptr = addrof volatileValue
    ll.storeVolatileU32(volatilePointer, 11)
    volatileWide u64 = 8
    volatileWidePointer ptr = addrof volatileWide
    ll.storeVolatileU64(volatileWidePointer, 12)
    if ll.loadVolatileU8(volatileBytePointer) != 2 || ll.loadVolatileU32(volatilePointer) != 11 || ll.loadVolatileU64(volatileWidePointer) != 12:
        throw errors.failure("llvm volatile wrappers failed")
    ..

    atomicByte u8 = 1
    atomicBytePointer ptr = addrof atomicByte
    ll.atomicStoreReleaseU8(atomicBytePointer, 2)
    if ll.atomicLoadAcquireU8(atomicBytePointer) != 2 || ll.atomicExchangeSequentialU8(atomicBytePointer, 3) != 2 || ll.atomicFetchAddSequentialU8(atomicBytePointer, 2) != 3 || ll.atomicFetchSubSequentialU8(atomicBytePointer, 1) != 5:
        throw errors.failure("llvm u8 atomics failed")
    ..
    ll.atomicStoreSequentialU8(atomicBytePointer, 9)
    if ll.atomicLoadSequentialU8(atomicBytePointer) != 9:
        throw errors.failure("llvm sequential u8 atomics failed")
    ..

    atomicWord u32 = 10
    atomicWordPointer ptr = addrof atomicWord
    ll.atomicStoreReleaseU32(atomicWordPointer, 11)
    if ll.atomicLoadAcquireU32(atomicWordPointer) != 11 || ll.atomicCompareExchangeAcquireU32(atomicWordPointer, 11, 12) != 11:
        throw errors.failure("llvm acquire u32 atomics failed")
    ..
    if ll.atomicExchangeSequentialU32(atomicWordPointer, 20) != 12 || ll.atomicFetchAddReleaseU32(atomicWordPointer, 2) != 20 || ll.atomicFetchSubAcqRelU32(atomicWordPointer, 1) != 22:
        throw errors.failure("llvm update u32 atomics failed")
    ..
    ll.atomicStoreSequentialU32(atomicWordPointer, 30)
    if ll.atomicLoadSequentialU32(atomicWordPointer) != 30 || ll.atomicLoadRelaxedU32(atomicWordPointer) != 30 || ll.atomicFetchAddSequentialU32(atomicWordPointer, 1) != 30 || ll.atomicFetchSubSequentialU32(atomicWordPointer, 1) != 31:
        throw errors.failure("llvm sequential u32 atomics failed")
    ..

    atomicWide u64 = 40
    atomicWidePointer ptr = addrof atomicWide
    ll.atomicStoreReleaseU64(atomicWidePointer, 41)
    if ll.atomicLoadAcquireU64(atomicWidePointer) != 41 || ll.atomicCompareExchangeSequentialU64(atomicWidePointer, 41, 42) != 41:
        throw errors.failure("llvm acquire u64 atomics failed")
    ..
    if ll.atomicExchangeSequentialU64(atomicWidePointer, 50) != 42 || ll.atomicFetchAddRelaxedU64(atomicWidePointer, 2) != 50 || ll.atomicFetchAddAcqRelU64(atomicWidePointer, 1) != 52:
        throw errors.failure("llvm update u64 atomics failed")
    ..
    ll.atomicStoreRelaxedU64(atomicWidePointer, 60)
    ll.atomicStoreSequentialU64(atomicWidePointer, 61)
    if ll.atomicLoadRelaxedU64(atomicWidePointer) != 61 || ll.atomicLoadSequentialU64(atomicWidePointer) != 61 || ll.atomicFetchAddSequentialU64(atomicWidePointer, 2) != 61 || ll.atomicFetchSubSequentialU64(atomicWidePointer, 1) != 63:
        throw errors.failure("llvm sequential u64 atomics failed")
    ..

    first ptr = raw
    second ptr = volatilePointer
    pointerSlot ptr = first
    pointerSlotAddress ptr = addrof pointerSlot
    ll.atomicStoreReleasePtr(pointerSlotAddress, second)
    if ll.atomicLoadAcquirePtr(pointerSlotAddress) != second:
        throw errors.failure("llvm pointer atomics failed")
    ..
    if ll.byteSwap16(4660) != 13330 || ll.byteSwap32(16909060) != 67305985 || ll.byteSwap64(1) != 72057594037927936:
        throw errors.failure("llvm byte swap failed")
    ..
    if ll.reverseBits8(1) != 128 || ll.reverseBits16(1) != 32768 || ll.reverseBits32(1) != 2147483648 || ll.reverseBits64(1) != 9223372036854775808:
        throw errors.failure("llvm bit reversal failed")
    ..
    if ll.populationCount8(15) != 4 || ll.populationCount16(15) != 4 || ll.populationCount32(15) != 4 || ll.populationCount64(15) != 4:
        throw errors.failure("llvm bit operation failed")
    ..
    if ll.leadingZeros32(1) != 31 || ll.leadingZeros64(0) != 64 || ll.trailingZeros32(8) != 3 || ll.trailingZeros64(8) != 3:
        throw errors.failure("llvm zero count failed")
    ..

    bits := ll.f64ToBits(1.5)
    smallBits := ll.f32ToBits(1.5)
    if ll.f64FromBits(bits) != 1.5 || ll.f32FromBits(smallBits) != 1.5:
        throw errors.failure("llvm bit cast failed")
    ..
    if ll.signExtendI8ToI64(-1) != -1 || ll.signExtendI16ToI64(-2) != -2 || ll.signExtendI32ToI64(-3) != -3 || ll.truncateI128ToI64(ll.signExtendI64ToI128(-4)) != -4:
        throw errors.failure("llvm signed conversion failed")
    ..
    if ll.zeroExtendU8ToU64(1) != 1 || ll.zeroExtendU16ToU64(2) != 2 || ll.zeroExtendU32ToU64(3) != 3 || ll.truncateU128ToU64(ll.zeroExtendU64ToU128(4)) != 4:
        throw errors.failure("llvm unsigned conversion failed")
    ..
    if ll.truncateI64ToI8(258) != 2 || ll.truncateI64ToI16(65538) != 2 || ll.truncateI64ToI32(4294967298) != 2:
        throw errors.failure("llvm signed truncation failed")
    ..
    if ll.truncateU64ToU8(258) != 2 || ll.truncateU64ToU16(65538) != 2 || ll.truncateU64ToU32(4294967298) != 2:
        throw errors.failure("llvm unsigned truncation failed")
    ..
    if ll.signedToF64(-4) != -4.0 || ll.unsignedToF64(4) != 4.0 || ll.f64ToSigned(-4.0) != -4 || ll.f64ToUnsigned(4.0) != 4:
        throw errors.failure("llvm numeric conversion failed")
    ..
    if ll.signedToUnsignedBits(-1) != 0 - 1 || ll.unsignedToSignedBits(7) != 7 || ll.unsigned32ToSignedBits(7) != 7:
        throw errors.failure("llvm integer bit preservation failed")
    ..
    if ll.expect(true, true) == false:
        throw errors.failure("llvm expect changed its input")
    ..
    ll.assume(true)
    ll.fenceSequentiallyConsistent()
    ll.pause()
..
