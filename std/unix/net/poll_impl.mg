mod net_poll_impl_posix
# POSIX poll fallback for systems without the Linux epoll backend.

use "std:c" as c
use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:atomic" as atomic
use "std:checked" as checked

PollFd(fd i32, events i16, returned i16)
Entry(token u64)
pub NativeEvent(token u64, flags u32)
pub Poller(allocator allocator.Allocator, descriptors PollFd*, entries Entry*, decoded NativeEvent*, capacity u64, count u64, wakeRead i32, wakeWrite i32, wakePending atomic.U8)

ext ext_poll poll(descriptors PollFd*, count u64, timeout i32) i32
ext ext_pipe pipe(descriptors i32*) i32
ext ext_read read(fd i32, buffer ptr, count u64) i64
ext ext_write write(fd i32, buffer ptr, count u64) i64
ext ext_close close(fd i32) i32

pub new(capacity u64) !$Poller:
    a := ctx.alloc
    storageCapacity := try checked.uAdd(capacity, 1)
    descriptors PollFd* = try a.allocT[PollFd](storageCapacity)
    onerror a.free(descriptors)
    entries Entry* = try a.allocT[Entry](storageCapacity)
    onerror a.free(entries)
    decoded NativeEvent* = try a.allocT[NativeEvent](capacity)
    onerror a.free(decoded)
    pipes := [2]i32
    if ext_pipe(pipes) != 0:
        throw errors.failure("poll wake pipe creation failed")
    ..
    descriptors[0] = PollFd(fd=pipes[0], events=1, returned=0)
    entries[0] = Entry(token=0 - 1)
    ret Poller(allocator=a, descriptors=descriptors, entries=entries, decoded=decoded, capacity=capacity, count=1, wakeRead=pipes[0], wakeWrite=pipes[1], wakePending=atomic.newU8(0))
..

find(poller Poller*, handle ptr) u64:
    fd i32 = cast.i64to32(cast.utoi(cast.ptou(handle)))
    for i u64 = 1 to poller.count:
        if poller.descriptors[i].fd == fd:
            ret i
        ..
    ..
    ret poller.count
..

nativeFlags(flags u32) i16:
    value i16 = 0
    if (flags & 1) != 0:
        value = value | 1
    ..
    if (flags & 2) != 0:
        value = value | 4
    ..
    ret value
..

pub add(poller Poller*, handle ptr, token u64, flags u32) !void:
    if poller.count > poller.capacity:
        throw errors.wouldOverflow("poller registration capacity reached")
    ..
    if find(poller, handle) != poller.count:
        throw errors.invalidArgument("socket is already registered")
    ..
    fd i32 = cast.i64to32(cast.utoi(cast.ptou(handle)))
    poller.descriptors[poller.count] = PollFd(fd=fd, events=nativeFlags(flags), returned=0)
    poller.entries[poller.count] = Entry(token=token)
    poller.count = poller.count + 1
..

pub modify(poller Poller*, handle ptr, token u64, flags u32) !void:
    index := find(poller, handle)
    if index == poller.count:
        throw errors.notFound("socket is not registered")
    ..
    poller.descriptors[index].events = nativeFlags(flags)
    poller.entries[index].token = token
..

pub remove(poller Poller*, handle ptr) !void:
    index := find(poller, handle)
    if index == poller.count:
        throw errors.notFound("socket is not registered")
    ..
    last u64 = poller.count - 1
    poller.descriptors[index] = poller.descriptors[last]
    poller.entries[index] = poller.entries[last]
    poller.count = last
..

decodeFlags(value i16) u32:
    flags u32 = 0
    if (value & 1) != 0:
        flags = flags | 1
    ..
    if (value & 4) != 0:
        flags = flags | 2
    ..
    if (value & (8 | 32)) != 0:
        flags = flags | 4
    ..
    if (value & 16) != 0:
        flags = flags | 8
    ..
    ret flags
..

pub wait(poller Poller*, limit u64, timeoutMs i64) !u64:
    timeout i32 = cast.i64to32(timeoutMs)
    ready i32 = ext_poll(poller.descriptors, poller.count, timeout)
    if ready < 0:
        throw errors.failure("poll failed")
    ..
    output u64 = 0
    i u64 = 0
    loop i < poller.count && output < limit:
        returned i16 = poller.descriptors[i].returned
        if returned != 0:
            if i == 0:
                byte u8
                ext_read(poller.wakeRead, addrof byte, 1)
                poller.wakePending.store(0)
            else:
                poller.decoded[output] = NativeEvent(token=poller.entries[i].token, flags=decodeFlags(returned))
                output = output + 1
            ..
            poller.descriptors[i].returned = 0
        ..
        i = i + 1
    ..
    ret output
..

pub eventAt(poller Poller*, index u64) NativeEvent:
    ret poller.decoded[index]
..

pub interrupt(poller Poller*) !void:
    if poller.wakePending.exchange(1) != 0:
        ret
    ..
    byte u8 = 1
    if ext_write(poller.wakeWrite, addrof byte, 1) < 0:
        poller.wakePending.store(0)
        throw errors.failure("poll wake failed")
    ..
..

pub close(poller Poller*) !void:
    ext_close(poller.wakeRead)
    ext_close(poller.wakeWrite)
    poller.allocator.free(poller.descriptors)
    poller.allocator.free(poller.entries)
    poller.allocator.free(poller.decoded)
..
