mod net_listener
# Callback-driven TCP listener with synchronous and worker-pool execution modes.

use "std:allocator" as allocator
use "std:context" as context
use "std:errors" as errors
use "std:net/address" as address
use "std:net/event_loop" as event_loop
use "std:net/poll" as poll
use "std:net/tcp" as tcp

pub alias AcceptCallback = (ptr, $tcp.Stream) !void

State(
    allocator allocator.Allocator
    server tcp.Listener
    callback AcceptCallback
    context ptr
)

pub Listener(
    state State*
    evloop event_loop.EventLoop
)

pub RunningListener(
    state State*
    evloop event_loop.RunningLoop
    active bool
)

onReady(raw ptr, token u64, flags u32) !void:
    state State* = none
    # SAFETY: new registers its live State pointer as the event-loop context.
    unsafe:
        state = raw
    ..
    if (flags & poll.READ) == 0:
        ret
    ..
    stream tcp.Stream, acceptError error = state.server.accept()
    if acceptError.nok():
        if errors.hasCode(acceptError, errors.ERR_WOULD_BLOCK):
            ret
        ..
        throw acceptError
    ..
    try state.callback(state.context, move stream)
..

pub new(endpoint address.Endpoint, backlog u32, capacity u64, commandCapacity u64, callback AcceptCallback, context ptr) !$Listener:
    a := ctx.alloc
    # SAFETY: state is freshly allocated and receives unique ownership of the
    # server before being published to the listener and callback.
    unsafe:
    if callback == none:
        throw errors.invalidArgument("accept callback cannot be none")
    ..
    state State* = try a.allocT[State](1)
    onerror a.free(state)
    server := try tcp.listenNonBlocking(endpoint, backlog)
    onerror server.close()
    evloop := try event_loop.new(a, capacity, commandCapacity)
    onerror evloop.close()
    state.allocator = a
    state.callback = callback
    state.context = context
    try evloop.watch(addrof server.socket, 0, poll.READ, onReady, state)
    state.server = move server
      ret Listener(state=state, evloop=move evloop)
    ..
..

Listener.localEndpoint() !address.Endpoint:
    if this.state == none:
        throw errors.invalidArgument("listener is not active")
    ..
    ret try this.state.server.localEndpoint()
..

Listener.run() !void:
    try this.evloop.run()
..

Listener.runOnce(timeoutMs i64) !u64:
    ret try this.evloop.runOnce(timeoutMs)
..

Listener.stop() !void:
    try this.evloop.stop()
..

destr Listener.runAsync() !$RunningListener:
    # SAFETY: runAsync transfers the unique state pointer and event loop into
    # RunningListener while clearing the consumed Listener slot.
    unsafe:
    if this.state == none:
        throw errors.invalidArgument("listener is not active")
    ..
    running := try this.evloop.runAsync()
    state := this.state
    this.state = none
      ret RunningListener(state=state, evloop=move running, active=true)
    ..
..

RunningListener.stop() !void:
    if this.active:
        try this.evloop.stop()
    ..
..

closeState(state State*) !void:
    # SAFETY: Listener/RunningListener uniquely owns state and invokes this
    # helper exactly once after the event loop has stopped using the server.
    unsafe:
        a := state.allocator
        try state.server.close()
        a.free(state)
    ..
..

closeStateResult(state State*) !bool:
    try closeState(state)
    ret true
..

destr RunningListener.await() !void:
    if this.active == false:
        throw errors.invalidArgument("running listener is not active")
    ..
    completed bool, runError error = awaitLoop(addrof this.evloop)
    closed bool, closeError error = closeStateResult(this.state)
    this.state = none
    this.active = false
    if runError.nok():
        throw runError
    ..
    if closeError.nok():
        throw closeError
    ..
..

awaitLoop(evloop event_loop.RunningLoop*) !bool:
    try evloop.await()
    ret true
..

destr Listener.close() !void:
    if this.state != none:
        try this.evloop.close()
        try closeState(this.state)
        this.state = none
    ..
..
