mod bitset

pub BitSet8(
    bits u8
)

BitSet8.set(bitIdx u8, value bool) void:
    this.setBit(1 << bitIdx, value)
..

BitSet8.flip(bitIdx u8) bool:
    ret this.flipBit(1 << bitIdx)
..

BitSet8.flipBit(bit u8) bool:
    newVal := not this.getBit(bit)
    this.setBit(bit, newVal)
    ret newVal
..

BitSet8.setBit(bit u8, value bool) void:
    if value:
        this.bits = this.bits | bit
    else:
        this.bits = this.bits & ~bit
    ..
..

BitSet8.get(bitIdx u8) bool:
    ret this.getBit(1 << bitIdx)
..

BitSet8.getBit(bit u8) bool:
    ret (this.bits & bit) != 0
..
