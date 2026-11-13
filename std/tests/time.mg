mod main
use "std:errors" as errors
use "std:time" as time
pub main() !void:
    start := time.ticks()
    if time.ticksToSec(time.secToTicks(2)) != 2 || time.ticksToMs(time.msToTicks(5)) != 5 || time.ticksToUs(time.usToTicks(5)) != 5 || time.ticksToNs(time.nsToTicks(100)) != 100:
        throw errors.failure("time conversion changed")
    ..
    if time.ticksToSecFloat(time.secFloatToTicks(0.5)) < 0.49 || time.runtime() < 0.0:
        throw errors.failure("floating time conversion changed")
    ..
    seconds := time.unixTimestamp()
    milliseconds := time.unixTimestampMs()
    if seconds == 0 || milliseconds / 1000 < seconds - 1 || time.unixTimestampUs() == 0 || time.unixTimestampNs() == 0:
        throw errors.failure("Unix timestamp changed")
    ..
    cpuBefore := time.processCpuTimeNs()
    time.sleep(1)
    if time.processCpuTimeNs() < cpuBefore || time.elapsedTicks(start) > time.ticks() || time.elapsedMs(start) == 0 || time.elapsedUs(start) == 0 || time.elapsedSec(start) > 1 || time.elapsedSecFloat(start) > 1.0:
        throw errors.failure("elapsed time changed")
    ..
..
