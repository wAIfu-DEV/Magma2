mod wake_impl_unix
# Unix wait-and-notify backend used by the portable wake module.


use "std:c" as c
@platform("linux", "freebsd", "netbsd", "openbsd")
link "pthread"

use "std:cast" as cast
use "std:errors" as errors
use "std:atomic" as atomic

const conditionStrategy u8 = 0

# Opaque, naturally aligned storage for pthread and POSIX semaphore objects.
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

pub Wake(
    strategy u8
    lock Opaque128
    conditionVariable Opaque128
    count atomic.U64
    waiters atomic.U32
    semaphore Opaque128
)

ext ext_pthread_mutex_init pthread_mutex_init(mutex ptr, attributes ptr) c.int
ext ext_pthread_mutex_lock pthread_mutex_lock(mutex ptr) c.int
ext ext_pthread_mutex_unlock pthread_mutex_unlock(mutex ptr) c.int
ext ext_pthread_mutex_destroy pthread_mutex_destroy(mutex ptr) c.int
ext ext_pthread_cond_init pthread_cond_init(condition ptr, attributes ptr) c.int
ext ext_pthread_cond_wait pthread_cond_wait(condition ptr, mutex ptr) c.int
ext ext_pthread_cond_signal pthread_cond_signal(condition ptr) c.int
ext ext_pthread_cond_destroy pthread_cond_destroy(condition ptr) c.int
ext ext_sem_init sem_init(semaphore ptr, shared c.int, value c.unsigned_int) c.int
ext ext_sem_wait sem_wait(semaphore ptr) c.int
ext ext_sem_post sem_post(semaphore ptr) c.int
ext ext_sem_destroy sem_destroy(semaphore ptr) c.int

nativeError(code i32, message str) error:
    ret errors.native(cast.u64to32(cast.itou(cast.i32to64(code))), message)
..

pub new(strategy u8) !$Wake:
    value Wake
    value.strategy = strategy
    value.count = atomic.newU64(0)
    value.waiters = atomic.newU32(0)
    code i32
    if strategy == conditionStrategy:
        code = ext_pthread_mutex_init(addrof value.lock, none)
        if code != 0:
            throw nativeError(code, "pthread_mutex_init failed")
        ..
        code = ext_pthread_cond_init(addrof value.conditionVariable, none)
        if code != 0:
            ext_pthread_mutex_destroy(addrof value.lock)
            throw nativeError(code, "pthread_cond_init failed")
        ..
    else:
        code = ext_sem_init(addrof value.semaphore, 0, 0)
        if code != 0:
            throw nativeError(code, "sem_init failed")
        ..
    ..
    ret value
..

pub wait(wake Wake*) !void:
    code i32
    if wake.strategy == conditionStrategy:
        available := wake.count.loadAcquire()
        loop available != 0:
            observed := wake.count.compareExchange(available, available - 1)
            if observed == available:
                ret
            ..
            available = observed
        ..
        wake.waiters.fetchAdd(1)
        code = ext_pthread_mutex_lock(addrof wake.lock)
        if code != 0:
            wake.waiters.fetchSub(1)
            throw nativeError(code, "pthread_mutex_lock failed")
        ..
        available = wake.count.loadAcquire()
        loop available == 0:
            code = ext_pthread_cond_wait(addrof wake.conditionVariable, addrof wake.lock)
            if code != 0:
                ext_pthread_mutex_unlock(addrof wake.lock)
                wake.waiters.fetchSub(1)
                throw nativeError(code, "pthread_cond_wait failed")
            ..
            available = wake.count.loadAcquire()
        ..
        loop wake.count.compareExchange(available, available - 1) != available:
            available = wake.count.loadAcquire()
            loop available == 0:
                code = ext_pthread_cond_wait(addrof wake.conditionVariable, addrof wake.lock)
                if code != 0:
                    ext_pthread_mutex_unlock(addrof wake.lock)
                    wake.waiters.fetchSub(1)
                    throw nativeError(code, "pthread_cond_wait failed")
                ..
                available = wake.count.loadAcquire()
            ..
        ..
        wake.waiters.fetchSub(1)
        code = ext_pthread_mutex_unlock(addrof wake.lock)
        if code != 0:
            throw nativeError(code, "pthread_mutex_unlock failed")
        ..
        ret
    ..
    code = ext_sem_wait(addrof wake.semaphore)
    if code != 0:
        throw nativeError(code, "sem_wait failed")
    ..
..

pub notify(wake Wake*) !void:
    code i32
    if wake.strategy == conditionStrategy:
        wake.count.fetchAdd(1)
        if wake.waiters.loadAcquire() == 0:
            ret
        ..
        code = ext_pthread_mutex_lock(addrof wake.lock)
        if code != 0:
            throw nativeError(code, "pthread_mutex_lock failed")
        ..
        code = ext_pthread_cond_signal(addrof wake.conditionVariable)
        unlockCode i32 = ext_pthread_mutex_unlock(addrof wake.lock)
        if code != 0:
            throw nativeError(code, "pthread_cond_signal failed")
        ..
        if unlockCode != 0:
            throw nativeError(unlockCode, "pthread_mutex_unlock failed")
        ..
        ret
    ..
    code = ext_sem_post(addrof wake.semaphore)
    if code != 0:
        throw nativeError(code, "sem_post failed")
    ..
..

pub free(wake Wake*) !void:
    code i32
    if wake.strategy == conditionStrategy:
        code = ext_pthread_cond_destroy(addrof wake.conditionVariable)
        if code != 0:
            throw nativeError(code, "pthread_cond_destroy failed")
        ..
        code = ext_pthread_mutex_destroy(addrof wake.lock)
        if code != 0:
            throw nativeError(code, "pthread_mutex_destroy failed")
        ..
    else:
        code = ext_sem_destroy(addrof wake.semaphore)
        if code != 0:
            throw nativeError(code, "sem_destroy failed")
        ..
    ..
..
