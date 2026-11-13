mod net_event_loop
# Readiness callback loop supporting synchronous execution or ownership transfer
# to an existing asynchronous worker pool.

use "std:allocator" as allocator
use "std:context" as context
use "std:atomic" as atomic
use "std:errors" as errors
use "std:future" as future
use "std:memory" as memory
use "std:adaptive_spinlock" as adaptive_spinlock
use "std:net/poll" as poll
use "std:net/socket" as socket

pub alias Callback = (ptr, u64, u32) !void

Registration(
    socket socket.Socket*
    token u64
    callback Callback
    context ptr
    active bool
)

Command(
    operation u8
    socket socket.Socket*
    token u64
    flags u32
    callback Callback
    context ptr
)

State(
    allocator allocator.Allocator
    poller poll.Poller
    events poll.Event*
    registrations Registration*
    capacity u64
    commands Command*
    commandCapacity u64
    commandHead u64
    commandTail u64
    commandCount u64
    commandLock adaptive_spinlock.AdaptiveSpinLock
    stopping atomic.U64
    running atomic.U64
)

pub EventLoop(
    state State*
)

RunTask(state State*)

pub RunningLoop(
    state State*
    completion future.Future[bool]
    active bool
)

pub new(a allocator.Allocator, capacity u64, commandCapacity u64) !$EventLoop:
    if capacity == 0 || commandCapacity == 0:
        throw errors.invalidArgument("event-loop capacities must be nonzero")
    ..
    state State* = try a.allocT[State](1)
    onerror a.free(state)
    memory.zero(state, sizeof State)
    nativePoller := try poll.new(a, capacity)
    onerror nativePoller.close()
    events poll.Event* = try a.allocT[poll.Event](capacity)
    onerror a.free(events)
    registrations Registration* = try a.allocT[Registration](capacity)
    onerror a.free(registrations)
    memory.zero(registrations, capacity * sizeof Registration)
    commands Command* = try a.allocT[Command](commandCapacity)
    onerror a.free(commands)
    state.allocator = a
    state.poller = move nativePoller
    state.events = events
    state.registrations = registrations
    state.capacity = capacity
    state.commands = commands
    state.commandCapacity = commandCapacity
    state.commandLock = adaptive_spinlock.new()
    state.stopping = atomic.newU64(0)
    state.running = atomic.newU64(0)
    ret EventLoop(state=state)
..

findByToken(state State*, token u64) u64:
    # SAFETY: registrations contains capacity initialized slots.
    unsafe:
    for i u64 = 0 to state.capacity:
        if state.registrations[i].active && state.registrations[i].token == token:
            ret i
        ..
    ..
      ret state.capacity
    ..
..

findVacant(state State*) u64:
    # SAFETY: registrations contains capacity initialized slots.
    unsafe:
    for i u64 = 0 to state.capacity:
        if state.registrations[i].active == false:
            ret i
        ..
    ..
      ret state.capacity
    ..
..

addNow(state State*, value socket.Socket*, token u64, flags u32, callback Callback, context ptr) !void:
    # SAFETY: findVacant returns a free capacity-bounded registration slot.
    unsafe:
    if callback == none:
        throw errors.invalidArgument("event callback cannot be none")
    ..
    if findByToken(state, token) != state.capacity:
        throw errors.invalidArgument("event token is already registered")
    ..
    slot := findVacant(state)
    if slot == state.capacity:
        throw errors.wouldOverflow("event-loop registration capacity reached")
    ..
    try state.poller.add(value, slot, flags)
      state.registrations[slot] = Registration(socket=value, token=token, callback=callback, context=context, active=true)
    ..
..

modifyNow(state State*, token u64, flags u32) !void:
    # SAFETY: findByToken returns an occupied capacity-bounded slot.
    unsafe:
    slot := findByToken(state, token)
    if slot == state.capacity:
        throw errors.notFound("event token is not registered")
    ..
    registration Registration* = addrof state.registrations[slot]
      try state.poller.modify(registration.socket, slot, flags)
    ..
..

removeNow(state State*, token u64) !void:
    # SAFETY: findByToken returns an occupied capacity-bounded slot.
    unsafe:
    slot := findByToken(state, token)
    if slot == state.capacity:
        throw errors.notFound("event token is not registered")
    ..
    registration Registration* = addrof state.registrations[slot]
    try state.poller.remove(registration.socket)
      memory.zero(registration, sizeof Registration)
    ..
..

EventLoop.watch(value socket.Socket*, token u64, flags u32, callback Callback, context ptr) !void:
    if this.state == none:
        throw errors.invalidArgument("event loop is not active")
    ..
    if this.state.running.load() != 0:
        throw errors.invalidArgument("use RunningLoop.watch while the loop runs asynchronously")
    ..
    try addNow(this.state, value, token, flags, callback, context)
..

EventLoop.modify(token u64, flags u32) !void:
    if this.state == none:
        throw errors.invalidArgument("event loop is not active")
    ..
    try modifyNow(this.state, token, flags)
..

EventLoop.unwatch(token u64) !void:
    if this.state == none:
        throw errors.invalidArgument("event loop is not active")
    ..
    try removeNow(this.state, token)
..

dequeue(state State*, output Command*) bool:
    # SAFETY: commandLock protects the capacity-sized ring and commandCount
    # proves commandHead is initialized.
    unsafe:
    state.commandLock.lock()
    if state.commandCount == 0:
        state.commandLock.unlock()
        ret false
    ..
    *output = state.commands[state.commandHead]
    state.commandHead = (state.commandHead + 1) % state.commandCapacity
    state.commandCount = state.commandCount - 1
    state.commandLock.unlock()
      ret true
    ..
..

processCommands(state State*) !void:
    command Command
    loop dequeue(state, addrof command):
        if command.operation == 1:
            try addNow(state, command.socket, command.token, command.flags, command.callback, command.context)
        elif command.operation == 2:
            try modifyNow(state, command.token, command.flags)
        elif command.operation == 3:
            try removeNow(state, command.token)
        ..
    ..
..

runOnceState(state State*, timeoutMs i64) !u64:
    # SAFETY: events and registrations each contain capacity slots; poller.wait
    # returns at most capacity events and tokens are checked before lookup.
    unsafe:
    try processCommands(state)
    if state.stopping.loadAcquire() != 0:
        ret 0
    ..
    events := slicesFromEvents(state.events, state.capacity)
    count := try state.poller.wait(events, timeoutMs)
    try processCommands(state)
    for i u64 = 0 to count:
        event := state.events[i]
        if event.token < state.capacity:
            registration Registration* = addrof state.registrations[event.token]
            if registration.active:
                try registration.callback(registration.context, registration.token, event.flags)
            ..
        ..
    ..
      ret count
    ..
..

slicesFromEvents(events poll.Event*, count u64) poll.Event[]:
    ret slice(__data=events, __count=count)
..

EventLoop.runOnce(timeoutMs i64) !u64:
    if this.state == none:
        throw errors.invalidArgument("event loop is not active")
    ..
    ret try runOnceState(this.state, timeoutMs)
..

EventLoop.run() !void:
    if this.state == none:
        throw errors.invalidArgument("event loop is not active")
    ..
    this.state.running.storeRelease(1)
    onerror this.state.running.storeRelease(0)
    loop this.state.stopping.loadAcquire() == 0:
        try runOnceState(this.state, -1)
    ..
    this.state.running.storeRelease(0)
..

EventLoop.stop() !void:
    if this.state != none:
        this.state.stopping.storeRelease(1)
        try this.state.poller.interrupt()
    ..
..

enqueue(state State*, command Command) !void:
    # SAFETY: commandLock protects the ring and the full check proves tail is a
    # free slot before publishing the command.
    unsafe:
    state.commandLock.lock()
    if state.commandCount == state.commandCapacity:
        state.commandLock.unlock()
        throw errors.wouldOverflow("event-loop command queue is full")
    ..
    state.commands[state.commandTail] = command
    state.commandTail = (state.commandTail + 1) % state.commandCapacity
    state.commandCount = state.commandCount + 1
    state.commandLock.unlock()
      try state.poller.interrupt()
    ..
..

RunningLoop.watch(value socket.Socket*, token u64, flags u32, callback Callback, context ptr) !void:
    if this.active == false:
        throw errors.invalidArgument("running loop is not active")
    ..
    # SAFETY: Command stores the callback's opaque context without dereferencing
    # it; the callback owner keeps it alive through await.
    unsafe:
        command := Command(operation=1, socket=value, token=token, flags=flags, callback=callback, context=context)
        try enqueue(this.state, command)
    ..
..

RunningLoop.modify(token u64, flags u32) !void:
    if this.active == false:
        throw errors.invalidArgument("running loop is not active")
    ..
    command := Command(operation=2, socket=none, token=token, flags=flags, callback=none, context=none)
    try enqueue(this.state, command)
..

RunningLoop.unwatch(token u64) !void:
    if this.active == false:
        throw errors.invalidArgument("running loop is not active")
    ..
    command := Command(operation=3, socket=none, token=token, flags=0, callback=none, context=none)
    try enqueue(this.state, command)
..

RunningLoop.stop() !void:
    if this.active:
        this.state.stopping.storeRelease(1)
        try this.state.poller.interrupt()
    ..
..

runWorker(task RunTask*) !bool:
    state := task.state
    state.running.storeRelease(1)
    onerror state.running.storeRelease(0)
    loop state.stopping.loadAcquire() == 0:
        try runOnceState(state, -1)
    ..
    state.running.storeRelease(0)
    ret true
..

destr EventLoop.runAsync() !$RunningLoop:
    if this.state == none:
        throw errors.invalidArgument("event loop is not active")
    ..
    task := RunTask(state=this.state)
    scheduler := ctx.exec
    completion := try future.new[bool, RunTask](scheduler, runWorker, task)
    state := this.state
    this.state = none
    ret RunningLoop(state=state, completion=move completion, active=true)
..

freeState(state State*) !void:
    # SAFETY: runAsync transfers unique ownership of the allocation and all its
    # fields to RunningLoop; freeState is called exactly once by await/close.
    unsafe:
        a := state.allocator
        try state.poller.close()
        a.free(state.events)
        a.free(state.registrations)
        a.free(state.commands)
        a.free(state)
    ..
..

destr RunningLoop.await() !void:
    if this.active == false:
        throw errors.invalidArgument("running loop is not active")
    ..
    completed bool, completionError error = this.completion.await()
    this.active = false
    cleanupError error = errors.ok()
    cleaned bool = true
    cleanupResult bool, capturedCleanup error = freeStateResult(this.state)
    if capturedCleanup.nok():
        cleanupError = capturedCleanup
    ..
    this.state = none
    if completionError.nok():
        throw completionError
    ..
    if cleanupError.nok():
        throw cleanupError
    ..
..

freeStateResult(state State*) !bool:
    try freeState(state)
    ret true
..

destr EventLoop.close() !void:
    if this.state != none:
        if this.state.running.load() != 0:
            throw errors.invalidArgument("await an asynchronous event loop instead of closing it")
        ..
        try freeState(this.state)
        this.state = none
    ..
..
