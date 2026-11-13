mod main

use "std:allocator" as allocator
use "std:context" as context
use "std:atomic" as atomic
use "std:builder" as builder
use "std:cast" as cast
use "std:errors" as errors
use "std:heap" as heap
use "std:slices" as slices
use "std:strconv" as strconv
use "std:strings" as strings
use "std:thread" as thread
use "std:thread_pool" as thread_pool
use "std:time" as time
use "std:net/address" as address
use "std:net/byte_order" as byte_order
use "std:net/dns" as dns
use "std:net/event_loop" as event_loop
use "std:net/listener" as net_listener
use "std:net/poll" as poll
use "std:net/socket" as socket
use "std:net/tcp" as tcp
use "std:net/udp" as udp
use "std:http" as http_client

CallbackContext(socket socket.Socket*, calls atomic.U64)
AcceptContext(calls atomic.U64)
HttpContext(calls atomic.U64, accepts atomic.U64)

onReadable(raw ptr, token u64, flags u32) !void:
    # SAFETY: registrations pass a live CallbackContext until loop await.
    context CallbackContext*
    unsafe:
        context = raw
    ..
    bytes := [8]u8
    count := try context.socket.recv(bytes, 8)
    if token != 91 || (flags & poll.READ) == 0 || count != 1:
        throw errors.failure("event-loop callback received invalid readiness")
    ..
    context.calls.fetchAdd(1)
..

onAccept(raw ptr, stream $tcp.Stream) !void:
    # SAFETY: the listener retains a live AcceptContext until await.
    context AcceptContext*
    unsafe:
        context = raw
    ..
    try stream.close()
    context.calls.fetchAdd(1)
..

onHttpAccept(raw ptr, stream $tcp.Stream) !void:
    # SAFETY: the listener retains a live HttpContext until await.
    context HttpContext*
    unsafe:
        context = raw
    ..
    defer stream.close()
    context.accepts.fetchAdd(1)
    requestNumber u64 = 0
    loop requestNumber < 2:
        requestBytes := [2048]u8
        received u64 = 0
        deadline := time.ticks() + time.msToTicks(2000)
        loop received == 0 && time.ticks() < deadline:
            count u64, receiveError error = stream.socket.recv(requestBytes, 2048)
            if receiveError.ok():
                received = count
            elif errors.hasCode(receiveError, errors.ERR_WOULD_BLOCK):
                thread.yield()
            else:
                throw receiveError
            ..
        ..
        if received == 0:
            throw errors.timedOut("HTTP test server did not receive request")
        ..
        response := "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nok"
        if requestNumber == 1:
            response = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: keep-alive\r\n\r\n2\r\nok\r\n0\r\n\r\n"
        ..
        sent u64 = 0
        loop sent < response.countBytes():
            sent = sent + try stream.socket.send(strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(response)) + sent), response.countBytes() - sent))
        ..
        context.calls.fetchAdd(1)
        requestNumber = requestNumber + 1
    ..
..

testAddress() !void:
    parsed := try address.parseIpv4("127.0.0.1")
    if parsed.equal(address.ipv4(127, 0, 0, 1)) == false:
        throw errors.failure("IPv4 parser changed")
    ..
    parsed6 := try address.parseIpv6("2001:db8::1")
    expected6 := address.ipv6(0x20010DB8, 0, 0, 1)
    if parsed6.equal(expected6) == false:
        throw errors.failure("IPv6 parser changed")
    ..
..

testByteOrder() !void:
    value16 u16 = 0
    byte_order.store16(addrof value16, 0x1234)
    value32 u32 = 0
    byte_order.store32(addrof value32, 0x12345678)
    # SAFETY: each pointer addresses the complete local integer tested below.
    unsafe:
        bytes16 u8* = addrof value16
        if bytes16[0] != 0x12 || bytes16[1] != 0x34 || byte_order.load16(addrof value16) != 0x1234:
            throw errors.failure("u16 network byte-order conversion changed")
        ..
        bytes32 u8* = addrof value32
        if bytes32[0] != 0x12 || bytes32[1] != 0x34 || bytes32[2] != 0x56 || bytes32[3] != 0x78 || byte_order.load32(addrof value32) != 0x12345678:
            throw errors.failure("u32 network byte-order conversion changed")
        ..
    ..
..

testDns() !void:
    a := ctx.alloc
    resolver := try dns.new(a, dns.defaultOptions())
    defer resolver.close()
    output := [16]address.Endpoint
    first := try resolver.resolveTo("localhost", "80", address.FAMILY_UNSPECIFIED, output)
    second := try resolver.resolveTo("localhost", "80", address.FAMILY_UNSPECIFIED, output)
    if first == 0 || second != first:
        throw errors.failure("DNS cache returned inconsistent results")
    ..
..

testUdp() !void:
    receiver := try udp.bind(address.loopbackIpv4(0))
    defer receiver.close()
    endpoint := try receiver.localEndpoint()
    sender := try udp.open(address.FAMILY_IPV4)
    defer sender.close()
    sent := try sender.sendTo("udp", endpoint)
    bytes := [8]u8
    received := try receiver.recvFrom(bytes, 8)
    if sent != 3 || received.count != 3 || received.source.address.isIpv4() == false:
        throw errors.failure("UDP loopback transfer failed")
    ..
..

testTcpPollAndAsync() !void:
    a := ctx.alloc
    listener := try tcp.listen(address.loopbackIpv4(0), 16)
    defer listener.close()
    endpoint := try listener.localEndpoint()
    client := try tcp.connect(endpoint)
    defer client.close()
    server := try listener.accept()
    defer server.close()

    poller := try poll.new(a, 8)
    defer poller.close()
    try poller.add(addrof server.socket, 77, poll.READ)
    try client.socket.send("p")
    events := [8]poll.Event
    count := try poller.wait(events, 1000)
    if count == 0 || events[0].token != 77 || (events[0].flags & poll.READ) == 0:
        throw errors.failure("poller did not report socket readiness")
    ..
    byte := [1]u8
    if try server.socket.recv(byte, 1) != 1:
        throw errors.failure("TCP loopback transfer failed")
    ..
    try poller.remove(addrof server.socket)

    evloop := try event_loop.new(a, 8, 8)
    cbcontext := CallbackContext(socket=addrof server.socket, calls=atomic.newU64(0))
    pool := try thread_pool.new(a, 1, 1, 8, 64)
    defer pool.close()
    ctx = context.new(a, pool.executor())
    running := try evloop.runAsync()
    defer:
        running.stop()
        running.await()
    ..
    try running.watch(addrof server.socket, 91, poll.READ, onReadable, addrof cbcontext)
    try client.socket.send("e")
    deadline := time.ticks() + time.msToTicks(2000)
    loop cbcontext.calls.loadAcquire() == 0 && time.ticks() < deadline:
        thread.yield()
    ..
    if cbcontext.calls.loadAcquire() != 1:
        throw errors.failure("asynchronous event loop did not dispatch")
    ..
..

testAsyncListener() !void:
    a := ctx.alloc
    accontext AcceptContext* = try a.allocT[AcceptContext](1)
    # SAFETY: allocT returned one writable AcceptContext slot exclusively owned
    # by this test until after the running listener is awaited.
    unsafe:
        *accontext = AcceptContext(calls=atomic.newU64(0))
    ..
    listener := try net_listener.new(address.loopbackIpv4(0), 16, 8, 8, onAccept, accontext)
    endpoint := try listener.localEndpoint()
    pool := try thread_pool.new(a, 1, 1, 8, 64)
    ctx = context.new(a, pool.executor())
    running := try listener.runAsync()
    client := try tcp.connect(endpoint)
    try client.close()
    deadline := time.ticks() + time.msToTicks(2000)
    loop accontext.calls.loadAcquire() == 0 && time.ticks() < deadline:
        thread.yield()
    ..
    try running.stop()
    try running.await()
    try pool.close()
    if accontext.calls.loadAcquire() != 1:
        a.free(accontext)
        throw errors.failure("asynchronous listener did not accept")
    ..
    a.free(accontext)
..

testHttpClient() !void:
    a := ctx.alloc
    htcontext HttpContext* = try a.allocT[HttpContext](1)
    defer a.free(htcontext)
    # SAFETY: allocT returned one writable HttpContext slot exclusively owned
    # by this test until after the running listener is awaited.
    unsafe:
        *htcontext = HttpContext(calls=atomic.newU64(0), accepts=atomic.newU64(0))
    ..
    listener := try net_listener.new(address.loopbackIpv4(0), 16, 8, 8, onHttpAccept, htcontext)
    endpoint := try listener.localEndpoint()
    pool := try thread_pool.new(a, 2, 2, 8, 64)
    defer pool.close()
    ctx = context.new(a, pool.executor())
    running := try listener.runAsync()
    defer:
        running.stop()
        running.await()
    ..
    portText := try strconv.formatUint(endpoint.port)
    defer portText.free()
    urlBuilder := try builder.new()
    defer urlBuilder.free()
    try urlBuilder.appendBorrowed("http://127.0.0.1:")
    try urlBuilder.appendBorrowed(portText)
    try urlBuilder.appendBorrowed("/test")
    url := try urlBuilder.build()
    defer url.free()
    client := try http_client.new(http_client.defaultOptions())
    defer client.close()
    headers http_client.Header[] = slices.fromPtr(none, 0)
    request := http_client.noBody("GET", url, headers)

    exchange := try client.start(request)
    loop try exchange.poll(2000) == false:
    ..
    response := try exchange.finish()
    defer response.close()
    exchange.releaseFinished()
    if response.statusCode != 200 || strings.compare(response.body, "ok") == false:
        throw errors.failure("polled HTTP response was invalid")
    ..
    pending := try client.sendAsync(request)
    asyncResponse := try pending.await()
    defer asyncResponse.close()
    if asyncResponse.statusCode != 200 || strings.compare(asyncResponse.body, "ok") == false:
        throw errors.failure("async HTTP response was invalid")
    ..
    if htcontext.calls.loadAcquire() != 2:
        throw errors.failure("HTTP test server did not receive both requests")
    ..
    if htcontext.accepts.loadAcquire() != 1:
        throw errors.failure("HTTP client did not reuse its connection")
    ..
..

pub main() !void:
    a := heap.allocator()
    try testAddress()
    try testByteOrder()
    try testDns()
    try testUdp()
    try testTcpPollAndAsync()
    try testAsyncListener()
    try testHttpClient()
..
