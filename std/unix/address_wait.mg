mod address_wait_unix
# Unix wait backend used by the portable wake module.
# @note Import `std:wake` instead of this implementation module.

use "std:wake" as wake_mod

# Unix fallback. Wake's counted condition variable closes the race between the
# atomic status check and entering the native wait.
pub Wait(
    wake wake_mod.Wake
)

pub new() !$Wait:
    value wake_mod.Wake = try wake_mod.new(wake_mod.condition())
    ret Wait(wake=move value)
..

pub wait(waiter Wait*, status u32*) !void:
    try waiter.wake.wait()
..

pub wake(waiter Wait*, status u32*) void:
    waiter.wake.notify()
..

pub free(waiter Wait*) void:
    # SAFETY: free consumes the embedded wake object through its owning Wait pointer.
    unsafe:
        waiter.wake.free()
    ..
..
