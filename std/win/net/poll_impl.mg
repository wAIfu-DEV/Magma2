mod net_poll_impl_win
# WSAPoll backend with a private loopback datagram used for immediate wakeup.

link "ws2_32"

use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:slices" as slices
use "std:net/address" as address
use "std:win/net/socket_impl" as socket_impl
use "std:atomic" as atomic
use "std:checked" as checked

PollFd(socket u64, events i16, returned i16)
Entry(token u64)
pub NativeEvent(token u64, flags u32)
pub Poller(allocator allocator.Allocator, descriptors PollFd*, entries Entry*, decoded NativeEvent*, capacity u64, count u64, wakeRead ptr, wakeWrite ptr, wakePending atomic.U8)

ext ext_WSAPoll WSAPoll(descriptors PollFd*, count u32, timeout i32) i32

pub new(capacity u64) !$Poller:
    a := ctx.alloc
    storageCapacity := try checked.uAdd(capacity, 1)
    descriptors PollFd* = try a.allocT[PollFd](storageCapacity)
    onerror a.free(descriptors)
    entries Entry* = try a.allocT[Entry](storageCapacity)
    onerror a.free(entries)
    decoded NativeEvent* = try a.allocT[NativeEvent](capacity)
    onerror a.free(decoded)
    wakeRead ptr = try socket_impl.openBlocking(address.FAMILY_IPV4, 2)
    onerror socket_impl.close(wakeRead)
    try socket_impl.bind(wakeRead, address.loopbackIpv4(0))
    endpoint := try socket_impl.localEndpoint(wakeRead)
    wakeWrite ptr = try socket_impl.openBlocking(address.FAMILY_IPV4, 2)
    onerror socket_impl.close(wakeWrite)
    try socket_impl.connect(wakeWrite, endpoint)
    descriptors[0] = PollFd(socket=cast.ptou(wakeRead), events=0x100, returned=0)
    entries[0] = Entry(token=0 - 1)
    ret Poller(allocator=a, descriptors=descriptors, entries=entries, decoded=decoded, capacity=capacity, count=1, wakeRead=wakeRead, wakeWrite=wakeWrite, wakePending=atomic.newU8(0))
..

find(poller Poller*, handle ptr) u64:
    value u64 = cast.ptou(handle)
    for i u64 = 1 to poller.count:
        if poller.descriptors[i].socket == value:
            ret i
        ..
    ..
    ret poller.count
..

nativeFlags(flags u32) i16:
    value i16 = 0
    if (flags & 1) != 0:
        value = value | 0x100
    ..
    if (flags & 2) != 0:
        value = value | 0x10
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
    poller.descriptors[poller.count] = PollFd(socket=cast.ptou(handle), events=nativeFlags(flags), returned=0)
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
    if (value & (0x100 | 0x200)) != 0:
        flags = flags | 1
    ..
    if (value & 0x10) != 0:
        flags = flags | 2
    ..
    if (value & (1 | 4)) != 0:
        flags = flags | 4
    ..
    if (value & 2) != 0:
        flags = flags | 8
    ..
    ret flags
..

pub wait(poller Poller*, limit u64, timeoutMs i64) !u64:
    ready i32 = ext_WSAPoll(poller.descriptors, cast.u64to32(poller.count), cast.i64to32(timeoutMs))
    if ready < 0:
        throw errors.failure("WSAPoll failed")
    ..
    output u64 = 0
    i u64 = 0
    loop i < poller.count && output < limit:
        returned i16 = poller.descriptors[i].returned
        if returned != 0:
            if i == 0:
                bytes := [64]u8
                socket_impl.recv(poller.wakeRead, bytes, 64)
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
    sent u64, sendError error = socket_impl.send(poller.wakeWrite, "w")
    if sendError.nok():
        poller.wakePending.store(0)
        throw sendError
    ..
..

pub close(poller Poller*) !void:
    try socket_impl.close(poller.wakeRead)
    try socket_impl.close(poller.wakeWrite)
    poller.allocator.free(poller.descriptors)
    poller.allocator.free(poller.entries)
    poller.allocator.free(poller.decoded)
..
