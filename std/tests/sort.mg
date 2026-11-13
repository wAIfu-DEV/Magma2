mod main
use "std:errors" as errors
use "std:sort" as sort

compareU64(a u64, b u64) i64:
    if a < b: ret -1 ..
    if a > b: ret 1 ..
    ret 0
..

assertSorted(values u64[], message str) !void:
    for i u64 = 1 to values.count():
        if values[i - 1] > values[i]: throw errors.failure(message) ..
    ..
..

pub main() !void:
    values := [3]u64
    values[0] = 3
    values[1] = 1
    values[2] = 2
    sort.insertion[u64](values, fn(a u64, b u64) i64:
        if a < b:
            ret -1
        elif a > b:
            ret 1
        ..
        ret 0
    ..)
    if values[0] != 1 || values[1] != 2 || values[2] != 3:
        throw errors.failure("sort behavior changed")
    ..
    sort.reverse[u64](values)
    if values[0] != 3 || values[2] != 1:
        throw errors.failure("sort reverse changed")
    ..

    heapValues := [12]u64
    quickValues := [12]u64
    source := [12]u64
    source[0] = 9
    source[1] = 1
    source[2] = 7
    source[3] = 1
    source[4] = 5
    source[5] = 3
    source[6] = 9
    source[7] = 0
    source[8] = 8
    source[9] = 2
    source[10] = 6
    source[11] = 4
    for i u64 = 0 to source.count():
        heapValues[i] = source[i]
        quickValues[i] = source[i]
    ..
    sort.heap[u64](heapValues, compareU64)
    sort.quick[u64](quickValues, compareU64)
    try assertSorted(heapValues, "heap sort behavior changed")
    try assertSorted(quickValues, "quick sort behavior changed")

    sorted := [6]u64
    reverseValues := [6]u64
    duplicates := [6]u64
    for i u64 = 0 to 6:
        sorted[i] = i
        reverseValues[i] = 5 - i
        duplicates[i] = i % 2
    ..
    sort.quick[u64](sorted, compareU64)
    sort.quick[u64](reverseValues, compareU64)
    sort.quick[u64](duplicates, compareU64)
    try assertSorted(sorted, "quick sort changed sorted input")
    try assertSorted(reverseValues, "quick sort changed reverse input")
    try assertSorted(duplicates, "quick sort changed duplicate input")

    largeHeap := [64]u64
    largeQuick := [64]u64
    largeSorted := [64]u64
    largeReverse := [64]u64
    largeDuplicates := [64]u64
    for i u64 = 0 to 64:
        value := (i * 37 + 19) % 53
        largeHeap[i] = value
        largeQuick[i] = value
        largeSorted[i] = i
        largeReverse[i] = 63 - i
        largeDuplicates[i] = i % 4
    ..
    sort.heap[u64](largeHeap, compareU64)
    sort.quick[u64](largeQuick, compareU64)
    sort.quick[u64](largeSorted, compareU64)
    sort.quick[u64](largeReverse, compareU64)
    sort.quick[u64](largeDuplicates, compareU64)
    try assertSorted(largeHeap, "heap sort changed larger input")
    try assertSorted(largeQuick, "quick sort changed larger input")
    try assertSorted(largeSorted, "quick sort changed larger sorted input")
    try assertSorted(largeReverse, "quick sort changed larger reverse input")
    try assertSorted(largeDuplicates, "quick sort changed larger duplicate input")

    empty := [0]u64
    singleton := [1]u64
    singleton[0] = 42
    sort.heap[u64](empty, compareU64)
    sort.quick[u64](empty, compareU64)
    sort.heap[u64](singleton, compareU64)
    sort.quick[u64](singleton, compareU64)
    if singleton[0] != 42: throw errors.failure("sort changed singleton") ..
..
