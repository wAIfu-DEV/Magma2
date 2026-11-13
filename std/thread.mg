mod thread
# Portable native threads with explicit joining and resource ownership.

use "std:errors" as errors
use "std:slices" as slices
use "std:cast" as cast

@platform("windows")
use "std:win/thread_impl" as impl_thread

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/thread_impl" as impl_thread

# A joinable native thread. The context is borrowed and must remain valid until
# the entry function has returned and the thread has been joined. The entry's
# integer result is reserved for the platform adapter and should normally be 0.
pub Thread(
    impl impl_thread.Thread
)

# Starts entry(context) on a new native thread.
# The returned Thread owns its native thread resource and must be joined once.
# Type parameter is used to ensure the correct context type is passed as argument.
# @complexity O(1), excluding platform thread creation
# @param entry function executed by the new thread
# @param context borrowed context passed to entry
# @returns owned joinable thread
# @mustcall join
# @example
#   worker := try thread.new[Context](runWorker, addrof context)
pub new[Ctx](entry fn(Ctx*) u64, context Ctx*) !$Thread:
    impl impl_thread.Thread = try impl_thread.spawn(entry, context)
    ret Thread(impl=impl)
..

# Waits until the thread finishes and releases its native thread resource.
# @complexity O(1) when finished; otherwise blocks
# @example
#   try worker.join()
destr Thread.join() !void:
    try impl_thread.join(addrof this.impl)
..

# Returns true once the entry function has finished. This does not consume the
# thread or release its native resources; join must still be called afterwards.
# @complexity O(1)
# @example
#   finished := try worker.isFinished()
Thread.isFinished() !bool:
    ret try impl_thread.isFinished(addrof this.impl)
..

# Joins every thread in the slice. All elements are consumed. If more than one
# join fails, the first error is returned after the remaining joins are tried.
# @complexity O(N), plus time spent waiting for unfinished threads
# @ownership Consumes every Thread in the slice.
# @example
#   try thread.joinAll(workers)
pub joinAll(threads Thread[]) !void:
    firstError error = errors.ok()
    base Thread* = cast.reinterpret[Thread](slices.toPtr(threads))
    for i u64 = 0 to slices.count(threads):
    
        implPtr ptr = cast.utop(cast.ptou(base) + (i * sizeof Thread))
        joined bool, joinError error = impl_thread.join(cast.reinterpret[impl_thread.Thread](implPtr))

        if joinError.nok() && firstError.ok():
            firstError = joinError
        ..
    ..
    if firstError.nok():
        throw firstError
    ..
..

# Gives the operating system an opportunity to schedule another ready thread.
# @complexity O(1), excluding scheduler cost
# @example
#   thread.yield()
pub yield() void:
    impl_thread.yield()
..
