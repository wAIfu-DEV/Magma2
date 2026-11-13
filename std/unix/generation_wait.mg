mod generation_wait_unix
# Unix generation-counter wait backend used by thread synchronization APIs.

use "std:wake" as wake_mod
use "std:llvm" as ll

pub Wait(
    wake wake_mod.Wake
)

pub new() !$Wait:
    value wake_mod.Wake = try wake_mod.new(wake_mod.condition())
    ret Wait(wake=move value)
..

pub observe(generation u32*) u32:
    ret ll.atomicLoadAcquireU32(generation)
..

advance(generation u32*) void:
    ll.atomicFetchAddReleaseU32(generation, 1)
..

pub signal(generation u32*) void:
    advance(generation)
..

pub wait(waiter Wait*, generation u32*, observed u32) !void:
    if observe(generation) != observed:
        ret
    ..
    try waiter.wake.wait()
..

pub wakeOne(waiter Wait*, generation u32*) void:
    advance(generation)
    waiter.wake.notify()
..

pub wakeAll(waiter Wait*, generation u32*, count u64) void:
    advance(generation)
    for i u64 = 0 to count:
        waiter.wake.notify()
    ..
..

pub free(waiter Wait*) void:
    # SAFETY: free consumes the embedded wake object through its owning Wait pointer.
    unsafe:
        waiter.wake.free()
    ..
..
