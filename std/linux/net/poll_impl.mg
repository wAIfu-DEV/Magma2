mod net_poll_impl_linux
# epoll backend with eventfd wakeup and a reusable native event slab.

use "std:c" as c
use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:memory" as memory
use "std:slices" as slices
use "std:atomic" as atomic

pub NativeEvent(token u64, flags u32)

pub Poller(
    allocator allocator.Allocator
    epollFd i32
    wakeFd i32
    raw u8*
    decoded NativeEvent*
    capacity u64
    wakePending atomic.U8
)

ext ext_epoll_create1 epoll_create1(flags c.int) c.int
ext ext_epoll_ctl epoll_ctl(epollFd c.int, operation c.int, fd c.int, event ptr) c.int
ext ext_epoll_wait epoll_wait(epollFd c.int, events ptr, maxEvents c.int, timeout c.int) c.int
ext ext_eventfd eventfd(initialValue c.unsigned_int, flags c.int) c.int
ext ext_read read(fd c.int, buffer ptr, count u64) i64
ext ext_write write(fd c.int, buffer ptr, count u64) i64
ext ext_close close(fd c.int) c.int

const WAKE_TOKEN u64 = 0xFFFFFFFFFFFFFFFF
const EVENT_SIZE u64 = 12

handleFd(handle ptr) i32:
    ret cast.i64to32(cast.utoi(cast.ptou(handle)))
..

nativeFlags(flags u32) u32:
    result u32 = 0
    if (flags & 1) != 0:
        result = result | 1
    ..
    if (flags & 2) != 0:
        result = result | 4
    ..
    # Always observe peer shutdown and errors.
    ret result | 0x2000
..

writeEvent(storage u8*, flags u32, token u64) void:
    memory.copy(addrof flags, storage, sizeof u32)
    memory.copy(addrof token, cast.utop(cast.ptou(storage) + 4), sizeof u64)
..

control(poller Poller*, operation i32, handle ptr, token u64, flags u32) !void:
    raw := [12]u8
    rawPointer u8* = cast.reinterpret[u8](slices.toPtr(raw))
    writeEvent(rawPointer, nativeFlags(flags), token)
    if ext_epoll_ctl(poller.epollFd, operation, handleFd(handle), rawPointer) != 0:
        throw errors.failure("epoll registration failed")
    ..
..

pub new(capacity u64) !$Poller:
    a := ctx.alloc
    epollFd i32 = ext_epoll_create1(0x80000)
    if epollFd < 0:
        throw errors.failure("epoll_create1 failed")
    ..
    onerror ext_close(epollFd)
    wakeFd i32 = ext_eventfd(0, 0x800 | 0x80000)
    if wakeFd < 0:
        throw errors.failure("eventfd failed")
    ..
    onerror ext_close(wakeFd)
    raw u8* = try a.allocT[u8](capacity * EVENT_SIZE)
    onerror a.free(raw)
    decoded NativeEvent* = try a.allocT[NativeEvent](capacity)
    onerror a.free(decoded)
    poller := Poller(allocator=a, epollFd=epollFd, wakeFd=wakeFd, raw=raw, decoded=decoded, capacity=capacity, wakePending=atomic.newU8(0))
    wakeHandle ptr = cast.utop(cast.itou(cast.i32to64(wakeFd)))
    try control(addrof poller, 1, wakeHandle, WAKE_TOKEN, 1)
    ret poller
..

pub add(poller Poller*, handle ptr, token u64, flags u32) !void:
    if token == WAKE_TOKEN:
        throw errors.invalidArgument("poll token is reserved")
    ..
    try control(poller, 1, handle, token, flags)
..

pub modify(poller Poller*, handle ptr, token u64, flags u32) !void:
    if token == WAKE_TOKEN:
        throw errors.invalidArgument("poll token is reserved")
    ..
    try control(poller, 3, handle, token, flags)
..

pub remove(poller Poller*, handle ptr) !void:
    if ext_epoll_ctl(poller.epollFd, 2, handleFd(handle), none) != 0:
        throw errors.failure("epoll removal failed")
    ..
..

decodeFlags(native u32) u32:
    flags u32 = 0
    if (native & 1) != 0:
        flags = flags | 1
    ..
    if (native & 4) != 0:
        flags = flags | 2
    ..
    if (native & 8) != 0:
        flags = flags | 4
    ..
    if (native & (16 | 0x2000)) != 0:
        flags = flags | 8
    ..
    ret flags
..

pub wait(poller Poller*, limit u64, timeoutMs i64) !u64:
    # SAFETY: raw and decoded each contain capacity event slots; epoll_wait is
    # limited accordingly and outputIndex never exceeds the returned count.
    unsafe:
    if limit == 0:
        ret 0
    ..
    timeout i32 = cast.i64to32(timeoutMs)
    count i32 = ext_epoll_wait(poller.epollFd, poller.raw, cast.u32toi32(cast.u64to32(limit)), timeout)
    if count < 0:
        throw errors.failure("epoll_wait failed")
    ..
    sourceIndex u64 = 0
    outputIndex u64 = 0
    loop sourceIndex < cast.itou(cast.i32to64(count)):
        event ptr = cast.utop(cast.ptou(poller.raw) + sourceIndex * EVENT_SIZE)
        nativeFlagsPtr u32* = event
        token u64
        memory.copy(cast.utop(cast.ptou(event) + 4), addrof token, sizeof u64)
        if token == WAKE_TOKEN:
            value u64
            ext_read(poller.wakeFd, addrof value, sizeof u64)
            poller.wakePending.store(0)
        else:
            poller.decoded[outputIndex] = NativeEvent(token=token, flags=decodeFlags(*nativeFlagsPtr))
            outputIndex = outputIndex + 1
        ..
        sourceIndex = sourceIndex + 1
    ..
      ret outputIndex
    ..
..

pub eventAt(poller Poller*, index u64) NativeEvent:
    # SAFETY: callers only use indices below the count returned by wait, whose
    # decoded output is stored in this capacity-sized array.
    unsafe:
        ret poller.decoded[index]
    ..
..

pub interrupt(poller Poller*) !void:
    if poller.wakePending.exchange(1) != 0:
        ret
    ..
    value u64 = 1
    result i64 = ext_write(poller.wakeFd, addrof value, sizeof u64)
    # EAGAIN means an unread wake is already pending, which is sufficient.
    if result < 0:
        poller.wakePending.store(0)
        ret
    ..
..

pub close(poller Poller*) !void:
    wakeCode i32 = ext_close(poller.wakeFd)
    epollCode i32 = ext_close(poller.epollFd)
    poller.allocator.free(poller.raw)
    poller.allocator.free(poller.decoded)
    poller.raw = none
    poller.decoded = none
    if wakeCode != 0 || epollCode != 0:
        throw errors.failure("poller close failed")
    ..
..
