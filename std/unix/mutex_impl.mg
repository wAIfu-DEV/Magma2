mod mutex_impl_unix
# Unix mutex backend used by the portable mutex module.


use "std:c" as c
@platform("linux", "freebsd", "netbsd", "openbsd")
link "pthread"

use "std:cast" as cast
use "std:errors" as errors

# Opaque, naturally aligned storage. 128 bytes covers the supported pthread ABIs.
Opaque128(
    part0 u128
    part1 u128
    part2 u128
    part3 u128
    part4 u128
    part5 u128
    part6 u128
    part7 u128
)

pub Mutex(
    storage Opaque128
)

ext ext_pthread_mutex_init    pthread_mutex_init(mutex Mutex*, attributes ptr) c.int
ext ext_pthread_mutex_lock    pthread_mutex_lock(mutex Mutex*) c.int
ext ext_pthread_mutex_unlock  pthread_mutex_unlock(mutex Mutex*) c.int
ext ext_pthread_mutex_destroy pthread_mutex_destroy(mutex Mutex*) c.int

nativeError(code i32, message str) error:
    ret errors.native(cast.u64to32(cast.itou(cast.i32to64(code))), message)
..

pub new() !Mutex:
    value Mutex
    code i32 = ext_pthread_mutex_init(addrof value, none)
    if code != 0:
        throw nativeError(code, "pthread_mutex_init failed")
    ..
    ret value
..

pub lock(mutex Mutex*) !void:
    code i32 = ext_pthread_mutex_lock(mutex)
    if code != 0:
        throw nativeError(code, "pthread_mutex_lock failed")
    ..
..

pub unlock(mutex Mutex*) !void:
    code i32 = ext_pthread_mutex_unlock(mutex)
    if code != 0:
        throw nativeError(code, "pthread_mutex_unlock failed")
    ..
..

pub free(mutex Mutex*) !void:
    code i32 = ext_pthread_mutex_destroy(mutex)
    if code != 0:
        throw nativeError(code, "pthread_mutex_destroy failed")
    ..
..
