mod win_net_runtime
# Shared, process-wide Winsock initialization.

link "ws2_32"

use "std:errors" as errors
use "std:cast" as cast
use "std:slices" as slices
use "std:llvm" as ll

ext ext_WSAStartup WSAStartup(version u16, data ptr) i32

global winsockState u8

loadState() u8:
    ret ll.atomicLoadAcquireU8(addrof winsockState)
..

claimInitialization() bool:
    ret ll.atomicCompareExchangeAcqRelU8(addrof winsockState, 0, 1) == 0
..

publishState(value u8) void:
    ll.atomicStoreReleaseU8(addrof winsockState, value)
..

pub ensure() !void:
    state := loadState()
    if state == 2:
        ret
    ..
    if state == 3: throw errors.failure("Winsock initialization previously failed") ..
    if claimInitialization():
        # WSADATA is smaller than this storage on every supported Windows ABI.
        data := [512]u8
        code i32 = ext_WSAStartup(0x0202, slices.toPtr(data))
        if code != 0:
            publishState(3)
            throw errors.native(cast.u64to32(cast.itou(cast.i32to64(code))), "WSAStartup failed")
        ..
        publishState(2)
        ret
    ..
    state = loadState()
    loop state == 1:
        state = loadState()
    ..
    if state == 2:
        ret
    ..
    throw errors.failure("Winsock initialization previously failed")
..
