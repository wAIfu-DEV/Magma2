mod thread_impl_unix
# Unix native-thread backend used by the portable thread module.


use "std:c" as c
@platform("linux", "freebsd", "netbsd", "openbsd")
link "pthread"

use "std:cast" as cast
use "std:errors" as errors
use "std:heap" as heap
use "std:context" as context
use "std:llvm" as ll

ext ext_pthread_create pthread_create(thread u64*, attributes ptr, startRoutine noctx fn(ptr) u64, argument ptr) c.int
ext ext_pthread_join   pthread_join(thread u64, result ptr) c.int
ext ext_sched_yield    sched_yield() c.int

pub Thread(
    handle u64
    launch Launch*
)

Launch(
    entry fn(ptr) u64
    context ptr
    magmaContext context.Ctx
    completed u8
)

storeCompleted(value u8*) void:
    ll.atomicStoreReleaseU8(value, 1)
..

loadCompleted(value u8*) u8:
    ret ll.atomicLoadAcquireU8(value)
..

noctx threadMain(raw ptr) u64:
    launch Launch*
    # SAFETY: spawn passes a live heap-allocated Launch as this thread context.
    unsafe:
        launch = raw
    ..
    ctx = launch.magmaContext
    result u64 = launch.entry(launch.context)
    storeCompleted(addrof launch.completed)
    ret result
..

pub spawn(entry fn(ptr) u64, context ptr) !$Thread:
    if entry == none:
        throw errors.invalidArgument("thread entry is null")
    ..

    launch Launch* = cast.reinterpret[Launch](try heap.alloc(sizeof Launch))
    onerror heap.free(launch)
    launch.entry = entry
    # SAFETY: Launch stores the opaque context required by its matching entry callback.
    unsafe:
    launch.context = context
    launch.magmaContext = ctx
    ..
    launch.completed = 0

    handle u64 = 0
    code i32 = ext_pthread_create(addrof handle, none, threadMain, launch)
    if code != 0:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(code))), "pthread_create failed")
    ..
    ret Thread(handle=handle, launch=launch)
..

pub isFinished(thread Thread*) !bool:
    if thread.handle == 0:
        throw errors.invalidArgument("thread is not joinable")
    ..
    ret loadCompleted(addrof thread.launch.completed) != 0
..

pub join(thread Thread*) !bool:
    if thread.handle == 0:
        throw errors.invalidArgument("thread is not joinable")
    ..
    code i32 = ext_pthread_join(thread.handle, none)
    if code != 0:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(code))), "pthread_join failed")
    ..
    heap.free(thread.launch)
    thread.handle = 0
    thread.launch = none
    ret true
..

pub yield() void:
    ext_sched_yield()
..
