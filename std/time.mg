mod time
# Monotonic timing, wall-clock timestamps, and duration conversion helpers.

use "std:cast" as cast

@platform("windows")
use "std:win/time_impl" as impl_time

@platform("linux", "android", "ios", "darwin", "freebsd", "netbsd", "openbsd")
use "std:unix/time_impl" as impl_time

# Reads the platform's monotonic high-resolution clock. Use this value only for
# measuring durations; it has no relationship to calendar time.
# @complexity O(1)
# @example
#   started := time.ticks()
pub ticks() u64:
    ret impl_time.ticks()
..

# Returns CPU time consumed by the current process in nanoseconds. Unlike
# runtime(), time spent blocked or sleeping is not included.
# @complexity O(1)
# @example
#   cpuNs := time.processCpuTimeNs()
pub processCpuTimeNs() u64:
    ret impl_time.processCpuTimeNs()
..

# Converts a monotonic tick duration to fractional seconds.
# @complexity O(1)
# @example
#   seconds := time.ticksToSecFloat(time.elapsedTicks(started))
pub ticksToSecFloat(tickCount u64) f64:
    freq u64 = impl_time.tickFrequency()
    ret cast.utof(tickCount) / cast.utof(freq)
..

# Returns the runtime in seconds as a float.
# @complexity O(1)
# @example
#   uptime := time.runtime()
pub runtime() f64:
    t u64 = ticks()
    ret ticksToSecFloat(t)
..

# Returns the number of seconds elapsed since the Unix epoch.
# @complexity O(1)
# @example
#   timestamp := time.unixTimestamp()
pub unixTimestamp() u64:
    ret impl_time.unixTimestamp()
..

# Returns the number of milliseconds elapsed since the Unix epoch.
# @complexity O(1)
# @example
#   timestampMs := time.unixTimestampMs()
pub unixTimestampMs() u64:
    ret impl_time.unixTimestampMs()
..

# Returns the number of microseconds elapsed since the Unix epoch.
# @complexity O(1)
# @example
#   timestampUs := time.unixTimestampUs()
pub unixTimestampUs() u128:
    ret impl_time.unixTimestampUs()
..

# Returns the number of nanoseconds elapsed since the Unix epoch.
# @complexity O(1)
# @example
#   timestampNs := time.unixTimestampNs()
pub unixTimestampNs() u128:
    ret impl_time.unixTimestampNs()
..

# Converts a tick duration to whole seconds, rounding down.
# @complexity O(1)
# @example
#   seconds := time.ticksToSec(elapsed)
pub ticksToSec(tickCount u64) u64:
    freq u64 = impl_time.tickFrequency()
    ret tickCount / freq
..

# Converts a tick duration to whole milliseconds, rounding down.
# @complexity O(1)
# @warning The intermediate multiplication can overflow for very large durations.
# @example
#   millis := time.ticksToMs(elapsed)
pub ticksToMs(tickCount u64) u64:
    freq u64 = impl_time.tickFrequency()
    ret (tickCount * 1000) / freq
..

# Converts a tick duration to whole microseconds, rounding down.
# @complexity O(1)
# @warning The intermediate multiplication can overflow for very large durations.
# @example
#   micros := time.ticksToUs(elapsed)
pub ticksToUs(tickCount u64) u64:
    freq u64 = impl_time.tickFrequency()
    ret (tickCount * 1000000) / freq
..

# Converts a tick duration to whole nanoseconds, rounding down.
# @complexity O(1)
# @warning The intermediate multiplication can overflow for very large durations.
# @example
#   nanos := time.ticksToNs(elapsed)
pub ticksToNs(tickCount u64) u64:
    freq u64 = impl_time.tickFrequency()
    ret (tickCount * 1000000000) / freq
..

# Converts whole seconds to monotonic clock ticks.
# @complexity O(1)
# @warning The result wraps if the duration exceeds u64 capacity.
# @example
#   deadlineDelta := time.secToTicks(5)
pub secToTicks(sec u64) u64:
    freq u64 = impl_time.tickFrequency()
    ret sec * freq
..

# Converts whole milliseconds to ticks, rounding down to the nearest tick.
# @complexity O(1)
# @warning The intermediate multiplication can overflow for very large durations.
# @example
#   timeout := time.msToTicks(250)
pub msToTicks(ms u64) u64:
    freq u64 = impl_time.tickFrequency()
    ret (ms * freq) / 1000
..

# Converts whole microseconds to ticks, rounding down to the nearest tick.
# @complexity O(1)
# @warning The intermediate multiplication can overflow for very large durations.
# @example
#   interval := time.usToTicks(500)
pub usToTicks(us u64) u64:
    freq u64 = impl_time.tickFrequency()
    ret (us * freq) / 1000000
..

# Converts whole nanoseconds to ticks, rounding down to the nearest tick.
# @complexity O(1)
# @warning The intermediate multiplication can overflow for very large durations.
# @example
#   interval := time.nsToTicks(50000)
pub nsToTicks(ns u64) u64:
    freq u64 = impl_time.tickFrequency()
    ret (ns * freq) / 1000000000
..

# Converts fractional seconds to ticks, truncating any fractional tick.
# @complexity O(1)
# @warning Negative, non-finite, or out-of-range inputs have target-dependent conversion behavior.
# @example
#   halfSecond := time.secFloatToTicks(0.5)
pub secFloatToTicks(sec f64) u64:
    freq u64 = impl_time.tickFrequency()
    ret cast.ftou(sec * cast.utof(freq))
..

# Returns the monotonic ticks elapsed since a value previously read by ticks().
# @complexity O(1)
# @example
#   elapsed := time.elapsedTicks(started)
pub elapsedTicks(startTicks u64) u64:
    t u64 = ticks()
    ret t - startTicks
..

# Returns whole milliseconds elapsed since a value previously read by ticks().
# @complexity O(1)
# @example
#   elapsed := time.elapsedMs(started)
pub elapsedMs(startTicks u64) u64:
    e u64 = elapsedTicks(startTicks)
    ret ticksToMs(e)
..

# Returns whole microseconds elapsed since a value previously read by ticks().
# @complexity O(1)
# @example
#   elapsed := time.elapsedUs(started)
pub elapsedUs(startTicks u64) u64:
    e u64 = elapsedTicks(startTicks)
    ret ticksToUs(e)
..

# Returns whole nanoseconds elapsed since a value previously read by ticks().
# @complexity O(1)
# @example
#   elapsed := time.elapsedNs(started)
pub elapsedNs(startTicks u64) u64:
    e u64 = elapsedTicks(startTicks)
    ret ticksToNs(e)
..

# Returns whole seconds elapsed since a value previously read by ticks().
# @complexity O(1)
# @example
#   elapsed := time.elapsedSec(started)
pub elapsedSec(startTicks u64) u64:
    e u64 = elapsedTicks(startTicks)
    ret ticksToSec(e)
..

# Returns fractional seconds elapsed since a value previously read by ticks().
# @complexity O(1)
# @example
#   elapsed := time.elapsedSecFloat(started)
pub elapsedSecFloat(startTicks u64) f64:
    e u64 = elapsedTicks(startTicks)
    ret ticksToSecFloat(e)
..

# Suspends the current thread for at least approximately milliSecs milliseconds.
# Scheduler granularity and system load may make the actual delay longer.
# @complexity O(1) setup; the call blocks for the requested duration
# @example
#   time.sleep(100)
pub sleep(milliSecs u64) void:
    impl_time.sleep(milliSecs)
..
 
