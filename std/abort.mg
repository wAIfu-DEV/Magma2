mod abort
# Cooperative abort signals for synchronous and asynchronous work.

use "std:allocator" as allocator
use "std:atomic" as atomic
use "std:errors" as errors
use "std:thread" as thread
use "std:time" as time

pub const REASON_NONE u64 = 0
pub const REASON_REQUESTED u64 = 1
pub const REASON_TIMED_OUT u64 = 2

State(
    allocator allocator.Allocator
    reason atomic.U64
    stopTimer atomic.U64
    deadlineTicks atomic.U64
    timer thread.Thread
    timerActive bool
)

# Borrowed and copyable. The owning Controller must outlive every Signal user.
pub Signal(state State*)

# Owns an abort signal and its optional relative-millisecond deadline.
# @mustcall close
pub Controller(state State*)

pub new() !$Controller:
    a := ctx.alloc
    state State* = try a.allocT[State](1)
    state.allocator = a
    state.reason = atomic.newU64(REASON_NONE)
    state.stopTimer = atomic.newU64(0)
    state.deadlineTicks = atomic.newU64(0)
    state.timerActive = false
    ret Controller(state=state)
..

Controller.signal() Signal:
    ret Signal(state=this.state)
..

Controller.abort() void:
    if this.state != none:
        this.state.reason.compareExchange(REASON_NONE, REASON_REQUESTED)
    ..
..

Controller.isAborted() bool:
    ret this.state != none && this.state.reason.loadAcquire() != REASON_NONE
..

Signal.isAborted() bool:
    ret this.state != none && this.state.reason.loadAcquire() != REASON_NONE
..

Signal.reason() u64:
    if this.state == none: ret REASON_NONE ..
    ret this.state.reason.loadAcquire()
..

Signal.check() !void:
    reason := this.reason()
    if reason == REASON_TIMED_OUT:
        throw errors.timedOut("operation deadline elapsed")
    elif reason == REASON_REQUESTED:
        throw errors.cancelled("operation aborted")
    ..
..

timerMain(state State*) u64:
    loop state.stopTimer.loadAcquire() == 0:
        deadline := state.deadlineTicks.loadAcquire()
        if deadline != 0 && time.ticks() >= deadline:
            state.reason.compareExchange(REASON_NONE, REASON_TIMED_OUT)
            ret 0
        ..
        time.sleep(10)
    ..
    ret 0
..

Controller.abortAfter(relativeMs u64) !void:
    if this.state == none:
        throw errors.invalidArgument("abort controller is closed")
    ..
    if relativeMs == 0:
        this.state.reason.compareExchange(REASON_NONE, REASON_TIMED_OUT)
        ret
    ..
    if this.state.deadlineTicks.load() != 0:
        throw errors.invalidArgument("abort deadline is already active")
    ..
    this.state.deadlineTicks.storeRelease(time.ticks() + time.msToTicks(relativeMs))
    if this.state.timerActive == false:
        this.state.timer = try thread.new[State](timerMain, this.state)
        this.state.timerActive = true
    ..
..

Controller.clearAbortDeadline() void:
    if this.state != none:
        this.state.deadlineTicks.storeRelease(0)
    ..
..

joinTimer(state State*) !bool:
    # SAFETY: Controller.close uniquely owns state and its timer.
    unsafe:
        try state.timer.join()
    ..
    ret true
..

destr Controller.close() void:
    if this.state != none:
        state := this.state
        state.stopTimer.storeRelease(1)
        if state.timerActive:
            joined bool, joinError error = joinTimer(state)
        ..
        state.allocator.free(state)
        this.state = none
    ..
..
