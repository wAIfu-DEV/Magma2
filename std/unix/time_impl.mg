mod time_impl_unix
# Unix clock backend used by the portable time module.


use "std:c" as c
use "std:cast" as cast

Timespec(
    sec i64,
    nsec i64,
)

ext ext_unix_clock_gettime clock_gettime(clockId c.int, value Timespec*) c.int
ext ext_unix_usleep        usleep(useconds c.unsigned_int) c.int
ext ext_unix_getrusage     getrusage(who c.int, usage RUsage*) c.int

# The first two fields of rusage are the user and system timeval values.
# Remaining ABI fields are covered by oversized, naturally aligned storage.
Opaque256(
    part0 u128
    part1 u128
    part2 u128
    part3 u128
    part4 u128
    part5 u128
    part6 u128
    part7 u128
    part8 u128
    part9 u128
    part10 u128
    part11 u128
    part12 u128
    part13 u128
    part14 u128
    part15 u128
)

RUsage(
    userSec i64
    userUsec i64
    systemSec i64
    systemUsec i64
    remaining Opaque256
)

pub processCpuTimeNs() u64:
    usage RUsage
    if ext_unix_getrusage(0, addrof usage) != 0:
        ret 0
    ..
    seconds u64 = cast.itou(usage.userSec + usage.systemSec)
    microseconds u64 = cast.itou(usage.userUsec + usage.systemUsec)
    ret (seconds * 1000000000) + (microseconds * 1000)
..

pub ticks() u64:
    value := Timespec(sec=0, nsec=0)
    ext_unix_clock_gettime(1, addrof value)
    ret cast.itou((value.sec * 1000000000) + value.nsec)
..

pub tickFrequency() u64:
    ret 1000000000
..

pub unixTimestamp() u64:
    value := Timespec(sec=0, nsec=0)
    ext_unix_clock_gettime(0, addrof value)
    ret cast.itou(value.sec)
..

pub unixTimestampMs() u64:
    value := Timespec(sec=0, nsec=0)
    ext_unix_clock_gettime(0, addrof value)
    sec u64 = cast.itou(value.sec)
    nsec u64 = cast.itou(value.nsec)
    ret (sec * 1000) + (nsec / 1000000)
..

pub unixTimestampUs() u128:
    value := Timespec(sec=0, nsec=0)
    ext_unix_clock_gettime(0, addrof value)
    sec u128 = cast.u64to128(cast.itou(value.sec))
    nsec u128 = cast.u64to128(cast.itou(value.nsec))
    ret (sec * 1000000) + (nsec / 1000)
..

pub unixTimestampNs() u128:
    value := Timespec(sec=0, nsec=0)
    ext_unix_clock_gettime(0, addrof value)
    sec u128 = cast.u64to128(cast.itou(value.sec))
    nsec u128 = cast.u64to128(cast.itou(value.nsec))
    ret (sec * 1000000000) + nsec
..

pub sleep(ms u64) void:
    ext_unix_usleep(cast.u64to32(ms * 1000))
..
