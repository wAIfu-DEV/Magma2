mod queue
# Allocator-backed first-in, first-out queues of owned generic values.

use "std:array"     as arr
use "std:allocator" as alc
# First-in, first-out collection that owns its enqueued values.
pub Queue[T](
    allocator alc.Allocator
    data     arr.Array[T]
    cleanup fn($T) void
)

# Creates an empty queue.
# @complexity O(1), excluding allocator cost
# @param a allocator retained for queue storage
# @param cleanup callback used for values discarded by clear or free, or none
# @ownership Release with Queue.free.
# @example
#   pending := try queue.new[u64](a, none)
pub new[T](cleanup fn($T) void) !$Queue[T]:
    a := ctx.alloc
    data := try arr.new[T](a)
    q Queue[T]
    q.allocator = a
    q.data = move data
    q.cleanup = cleanup
    ret q
..

# Transfers an item to the back of the queue.
# @complexity Amortized O(1); O(N) when storage grows
# @example
#   try pending.enqueue(42)
Queue[T].enqueue(item $T) !void:
    try this.data.pushRight(this.allocator, move item)
..

# Removes and returns ownership of the oldest item.
# @complexity Amortized O(1); O(N) when storage shrinks
# @throws wouldOverflow when the queue is empty
# @example
#   item := try pending.dequeue()
Queue[T].dequeue() !$T:
    
    ret try this.data.popLeft(this.allocator)
..

# Returns a volatile borrowed view in dequeue order.
# @complexity O(1)
# @warning Enqueueing, dequeueing, clearing, or freeing invalidates the view.
Queue[T].view() T[]:
    ret this.data.view()
..

# Returns the number of queued items.
# @complexity O(1)
Queue[T].count() u64:
    ret this.data.count()
..

# Removes and cleans up every item while keeping the queue reusable.
# @complexity O(N), plus cleanup cost
# @example
#   try pending.clear()
Queue[T].clear() !void:
    try this.data.clearShrink(this.allocator, this.cleanup)
..

# Cleans up all remaining items and releases queue storage.
# @complexity O(N), plus cleanup cost
# @example
#   pending.free()
destr Queue[T].free() void:
    this.data.free(this.allocator, this.cleanup)
..
