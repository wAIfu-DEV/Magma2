mod cpu
# Portable information about processors available to the current process.

@platform("windows")
use "std:win/cpu_impl" as impl_cpu

@platform("linux")
use "std:unix/cpu_impl_linux" as impl_cpu

@platform("android")
use "std:unix/cpu_impl_android" as impl_cpu

@platform("ios", "darwin", "freebsd", "openbsd")
use "std:unix/cpu_impl_posix" as impl_cpu

@platform("netbsd")
use "std:unix/cpu_impl_netbsd" as impl_cpu

# Returns the number of logical CPU cores currently available to the process.
# The result is always at least one, even when the operating-system query fails.
# @complexity O(1), excluding the operating-system query
# @example
#   workerCount := cpu.coreCount()
pub coreCount() u64:
    count u64 = impl_cpu.coreCount()
    if count == 0:
        ret 1
    ..
    ret count
..
