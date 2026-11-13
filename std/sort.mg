mod sort
# In-place generic sorting and reversal operations for slices.

use "std:slices" as slices

# Sorts a slice in ascending comparator order using stable insertion sort.
# @complexity O(N²) comparisons and swaps; O(N) for an already sorted slice
# @param in mutable slice to sort
# @param compare comparator returning a negative, zero, or positive value
# @example
#   sort.insertion(values, compare)
pub insertion[T](in T[], compare (T, T) i64) void:
    n := slices.count(in)
    for i u64 = 1 to n:
        j := i
        prev := j - 1
        # The outer loop establishes i < n; each iteration maintains j <= i,
        # and j > 0 makes prev = j - 1 a valid predecessor.
        bounded j < n, prev < n:
            loop j > 0 && compare(in[j], in[prev]) < 0:
                tmp := in[j]
                in[j] = in[prev]
                in[prev] = tmp
                j = j - 1
                prev = j - 1
            ..
        ..
    ..
..

swapAt[T](in T[], left u64, right u64) void:
    bounded left < slices.count(in), right < slices.count(in):
        tmp := in[left]
        in[left] = in[right]
        in[right] = tmp
    ..
..

siftDown[T](in T[], root u64, end u64, compare (T, T) i64) void:
    loop root < end / 2:
        child := root * 2 + 1
        selected := root
        bounded root < end, child < end, end <= slices.count(in):
            if compare(in[selected], in[child]) < 0:
                selected = child
            ..
            if child + 1 < end:
                bounded selected < end, child + 1 < end, end <= slices.count(in):
                    if compare(in[selected], in[child + 1]) < 0:
                        selected = child + 1
                    ..
                ..
            ..
        ..
        if selected == root:
            ret
        ..
        swapAt[T](in, root, selected)
        root = selected
    ..
..

# Sorts a slice in ascending comparator order using in-place heap sort.
# @complexity O(N log N) comparisons in all cases; O(1) extra space
# @param in mutable slice to sort
# @param compare comparator returning a negative, zero, or positive value
pub heap[T](in T[], compare (T, T) i64) void:
    n := slices.count(in)
    if n < 2:
        ret
    ..
    start := n / 2
    loop start > 0:
        start = start - 1
        siftDown[T](in, start, n, compare)
    ..
    end := n
    loop end > 1:
        end = end - 1
        swapAt[T](in, 0, end)
        siftDown[T](in, 0, end, compare)
    ..
..

quickRange[T](in T[], low u64, high u64, compare (T, T) i64) void:
    loop high - low > 16:
        pivotIndex := low + (high - low) / 2
        pivot T
        bounded pivotIndex < slices.count(in): pivot = in[pivotIndex] ..
        left := low
        current := low
        right := high
        loop current < right:
            comparison i64
            bounded current < slices.count(in): comparison = compare(in[current], pivot) ..
            if comparison < 0:
                swapAt[T](in, left, current)
                left = left + 1
                current = current + 1
            elif comparison > 0:
                right = right - 1
                swapAt[T](in, current, right)
            else:
                current = current + 1
            ..
        ..
        # Recurse into the smaller partition and iterate over the larger one,
        # bounding recursion depth even on adversarial inputs.
        if left - low < high - right:
            quickRange[T](in, low, left, compare)
            low = right
        else:
            quickRange[T](in, right, high, compare)
            high = left
        ..
    ..
    # Insertion sort the small remaining range without allocating a subslice.
    for i u64 = low + 1 to high:
        j := i
        loop j > low:
            previous := j - 1
            shouldSwap bool
            bounded j < slices.count(in), previous < slices.count(in):
                shouldSwap = compare(in[j], in[previous]) < 0
            ..
            if shouldSwap == false:
                break
            ..
            swapAt[T](in, j, previous)
            j = previous
        ..
    ..
..

# Sorts a slice in ascending comparator order using three-way quicksort.
# Three-way partitioning avoids duplicate-heavy degeneration, while smaller-
# side recursion bounds auxiliary stack use to O(log N).
# @complexity O(N log N) average; O(N²) worst case; O(log N) stack space
# @param in mutable slice to sort
# @param compare comparator returning a negative, zero, or positive value
pub quick[T](in T[], compare (T, T) i64) void:
    if slices.count(in) < 2:
        ret
    ..
    quickRange[T](in, 0, slices.count(in), compare)
..

# Reverses a slice in place.
# @complexity O(N)
# @param in mutable slice to reverse
# @example
#   sort.reverse(values)
pub reverse[T](in T[]) void:
    n := slices.count(in)
    for i u64 = 0 to n / 2:
        right := n - i - 1
        # i < n/2 and right = n-i-1 place both indices within the slice.
        bounded i < n, right < n:
            tmp := in[i]
            in[i] = in[right]
            in[right] = tmp
        ..
    ..
..
