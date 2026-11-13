mod http
# Portable HTTP/1.1 client over std/net with client-owned connection pooling.

use "std:allocator" as allocator
use "std:context" as context
use "std:builder" as builder
use "std:cast" as cast
use "std:errors" as errors
use "std:future" as future
use "std:abort" as abort
use "std:memory" as memory
use "std:adaptive_spinlock" as adaptive_spinlock
use "std:reader" as reader
use "std:slices" as slices
use "std:strconv" as strconv
use "std:strings" as strings
use "std:net/address" as address
use "std:net/dns" as dns
use "std:net/poll" as poll
use "std:net/socket" as socket
use "std:net/tls" as tls
use "std:checked" as checked

pub Header(
    name str
    value str
)

pub Request(
    method str
    url str
    headers Header[]
    body reader.Reader
    bodyLength u64
)

pub noBody(method str, url str, headers Header[]) Request:
    ret Request(method=method, url=url, headers=headers, body=memory.zeroValue[reader.Reader](), bodyLength=0)
..

pub Options(
    dns dns.Options
    ioTimeoutMs i64
    maxResponseBytes u64
    readBufferBytes u64
    connectionCapacity u64
)

pub defaultOptions() Options:
    ret Options(dns=dns.defaultOptions(), ioTimeoutMs=30000, maxResponseBytes=16 * 1024 * 1024, readBufferBytes=16384, connectionCapacity=32)
..

Connection(
    host $str
    service $str
    socket socket.Socket
    tls tls.Session
    secure bool
    active bool
    reusable bool
    inUse bool
)

pub Client(
    allocator allocator.Allocator
    resolver dns.Resolver
    tlsContext tls.Context
    connections Connection*
    connectionCapacity u64
    connectionLock adaptive_spinlock.AdaptiveSpinLock
    options Options
    active bool
)

pub Response(
    allocator allocator.Allocator
    statusCode u16
    rawHeaders $str
    body $str
    active bool
)

ParsedUrl(
    host $str
    service $str
    target $str
    secure bool
)

pub Exchange(
    allocator allocator.Allocator
    client Client*
    connection u64
    socket socket.Socket*
    poller poll.Poller
    events poll.Event*
    request $str
    sent u64
    received u8*
    receivedCount u64
    receivedCapacity u64
    maxResponseBytes u64
    readBufferBytes u64
    headerEnd u64
    expectedTotal u64
    chunked bool
    closeDelimited bool
    complete bool
    active bool
)

SendTask(
    client Client*
    request Request
    external abort.Signal
    hasExternal bool
)

pub new(options Options) !$Client:
    a := ctx.alloc
    if options.ioTimeoutMs < 0 || options.maxResponseBytes == 0 || options.readBufferBytes == 0 || options.dns.maxResults > 16 || options.connectionCapacity == 0:
        throw errors.invalidArgument("invalid HTTP client limits")
    ..
    resolver := try dns.new(a, options.dns)
    onerror resolver.close()

    tlsContext := try tls.newContext()
    onerror tlsContext.close()

    connections := try a.allocT[Connection](options.connectionCapacity)
    onerror a.free(connections)
    
    memory.zero(connections, options.connectionCapacity * sizeof Connection)
    guard := adaptive_spinlock.new()
    client Client
    client.allocator = a
    client.resolver = move resolver
    client.tlsContext = move tlsContext
    client.connections = connections
    client.connectionCapacity = options.connectionCapacity
    client.connectionLock = move guard
    client.options = options
    client.active = true
    ret client
..

findSchemeEnd(url str) u64:
    n := url.countBytes()
    i u64 = 0
    loop i + 2 < n:
        if strings.byteAt(url, i) == 58 && strings.byteAt(url, i + 1) == 47 && strings.byteAt(url, i + 2) == 47:
            ret i
        ..
        i = i + 1
    ..
    ret n
..

parseUrl(url str) !$ParsedUrl:
    a := ctx.alloc
    n := url.countBytes()
    schemeEnd := findSchemeEnd(url)
    if schemeEnd == n || schemeEnd == 0:
        throw errors.invalidArgument("HTTP URL must be absolute")
    ..
    secure bool = false
    if schemeEnd == 5 && strings.byteAt(url, 0) == 104 && strings.byteAt(url, 1) == 116 && strings.byteAt(url, 2) == 116 && strings.byteAt(url, 3) == 112 && strings.byteAt(url, 4) == 115:
        secure = true
    elif schemeEnd != 4 || strings.byteAt(url, 0) != 104 || strings.byteAt(url, 1) != 116 || strings.byteAt(url, 2) != 116 || strings.byteAt(url, 3) != 112:
        throw errors.invalidArgument("HTTP URL scheme must be http or https")
    ..
    authorityStart := schemeEnd + 3
    authorityEnd := authorityStart
    loop authorityEnd < n && strings.byteAt(url, authorityEnd) != 47:
        authorityEnd = authorityEnd + 1
    ..
    if authorityEnd == authorityStart:
        throw errors.invalidArgument("HTTP URL host is empty")
    ..
    colon := authorityEnd
    for i := authorityStart to authorityEnd:
        if strings.byteAt(url, i) == 58:
            colon = i
        ..
    ..
    hostEnd := authorityEnd
    if colon < authorityEnd:
        hostEnd = colon
    ..
    host := try strings.substring(url, authorityStart, hostEnd)
    onerror host.free()

    service str
    if colon < authorityEnd:
        service = try strings.substring(url, colon + 1, authorityEnd)
        onerror service.free()
        parsedPort := try strconv.parseUint(service)
        if parsedPort == 0 || parsedPort > 65535:
            throw errors.invalidArgument("HTTP port is out of range")
        ..
    else:
        if secure:
            service = try strings.copy("443")
        else:
            service = try strings.copy("80")
        ..
    ..
    onerror service.free()

    target str
    if authorityEnd == n:
        target = try strings.copy("/")
    else:
        target = try strings.substring(url, authorityEnd, n)
    ..
    ret ParsedUrl(host=move host, service=move service, target=move target, secure=secure)
..

destr ParsedUrl.free() void:
    a := ctx.alloc
    this.host.free()
    this.service.free()
    this.target.free()
..

buildRequest(request Request, parsed ParsedUrl*) !$str:
    a := ctx.alloc
    if request.method.countBytes() == 0:
        throw errors.invalidArgument("HTTP method is empty")
    ..
    output := try builder.newWithCapacity(64)
    defer output.free()

    try output.appendBorrowed(request.method)
    try output.appendBorrowed(" ")
    try output.appendBorrowed(parsed.target)
    try output.appendBorrowed(" HTTP/1.1\r\nHost: ")
    try output.appendBorrowed(parsed.host)

    defaultPort := strings.compare(parsed.service, "80") && parsed.secure == false
    if parsed.secure:
        defaultPort = strings.compare(parsed.service, "443")
    ..
    if defaultPort == false:
        try output.appendBorrowed(":")
        try output.appendBorrowed(parsed.service)
    ..
    try output.appendBorrowed("\r\nConnection: keep-alive\r\n")
    if request.bodyLength > 0:
        length := try strconv.formatUint(request.bodyLength)
        try output.appendBorrowed("Content-Length: ")
        try output.appendOwned(move length)
        try output.appendBorrowed("\r\n")
    ..

    for i u64 = 0 to slices.count(request.headers):
        try output.appendBorrowed(request.headers[i].name)
        try output.appendBorrowed(": ")
        try output.appendBorrowed(request.headers[i].value)
        try output.appendBorrowed("\r\n")
    ..
    try output.appendBorrowed("\r\n")
    if request.bodyLength > 0:
        contents := try request.body.read(request.bodyLength)
        if contents.countBytes() != request.bodyLength:
            contents.free()
            throw errors.failure("HTTP request body ended before its declared length")
        ..
        try output.appendOwned(move contents)
    ..
    ret try output.build()
..

findReusable(client Client*, host str, service str, secure bool) u64:
    # SAFETY: connections contains connectionCapacity initialized slots and the
    # active flag guards all owned fields.
    unsafe:
    for i u64 = 0 to client.connectionCapacity:
        connection Connection* = addrof client.connections[i]
        if connection.active && connection.reusable && connection.inUse == false && connection.secure == secure && strings.compare(connection.host, host) && strings.compare(connection.service, service):
            ret i
        ..
    ..
      ret client.connectionCapacity
    ..
..

findEmpty(client Client*) u64:
    # SAFETY: connections contains exactly connectionCapacity initialized slots.
    unsafe:
    for i u64 = 0 to client.connectionCapacity:
        if client.connections[i].active == false:
            ret i
        ..
    ..
      ret client.connectionCapacity
    ..
..

Client.acquire(host str, service str, secure bool) !u64:
    # SAFETY: connectionLock serializes occupancy metadata; active/inUse are the
    # slot state, and owned transport/host/service values are published once.
    unsafe:
    this.connectionLock.lock()
    existing := findReusable(this, host, service, secure)
    if existing < this.connectionCapacity:
        this.connections[existing].inUse = true
        this.connectionLock.unlock()
        ret existing
    ..
    slot := findEmpty(this)
    if slot == this.connectionCapacity:
        this.connectionLock.unlock()
        throw errors.wouldOverflow("HTTP connection pool capacity reached")
    ..
    # Reserve the slot before the native connect so concurrent requests cannot
    # claim it. Different requests may intentionally establish parallel
    # connections to the same origin.
    this.connections[slot].active = true
    this.connections[slot].inUse = true
    this.connections[slot].reusable = false
    this.connectionLock.unlock()

    ownedHost str, hostError error = strings.copy(host)
    if hostError.nok():
        this.connections[slot].active = false
        this.connections[slot].inUse = false
        throw hostError
    ..
    ownedService str, serviceError error = strings.copy(service)
    if serviceError.nok():
        ownedHost.free()
        this.connections[slot].active = false
        this.connections[slot].inUse = false
        throw serviceError
    ..
    endpoints := [16]address.Endpoint
    endpointView address.Endpoint[] = endpoints
    count u64, resolveError error = this.resolver.resolveTo(host, service, address.FAMILY_UNSPECIFIED, endpointView)
    if resolveError.nok() || count == 0:
        ownedHost.free()
        ownedService.free()
        this.connections[slot].active = false
        this.connections[slot].inUse = false
        if resolveError.nok():
            throw resolveError
        ..
        throw errors.notFound("HTTP host has no addresses")
    ..
    transport socket.Socket, connectError error = socket.open(endpoints[0].address.family, socket.TYPE_STREAM)
    if connectError.nok():
        ownedHost.free()
        ownedService.free()
        this.connections[slot].active = false
        this.connections[slot].inUse = false
        throw connectError
    ..
    connectResult bool, connectFailure error = connectSocket(addrof transport, endpoints[0])
    if connectFailure.nok():
        transport.close()
        ownedHost.free()
        ownedService.free()
        this.connections[slot].active = false
        this.connections[slot].inUse = false
        throw connectFailure
    ..
    connection Connection* = addrof this.connections[slot]
    connection.host = move ownedHost
    connection.service = move ownedService
    connection.socket = move transport
    connection.secure = secure
    if secure:
        secured tls.Session, tlsError error = this.tlsContext.open(addrof connection.socket, host)
        if tlsError.nok():
            connection.socket.close()
            connection.host.free()
            connection.service.free()
            connection.active = false
            connection.inUse = false
            throw tlsError
        ..
        connection.tls = move secured
    ..
    connection.reusable = true
      ret slot
    ..
..

connectSocket(transport socket.Socket*, endpoint address.Endpoint) !bool:
    try transport.connect(endpoint)
    try transport.setNonBlocking(true)
    ret true
..

Client.release(index u64, reusable bool) !void:
    # SAFETY: the lock protects the capacity-sized connection table and the
    # explicit index check precedes every access.
    unsafe:
    this.connectionLock.lock()
    if index < this.connectionCapacity && this.connections[index].active:
        this.connections[index].reusable = this.connections[index].reusable && reusable
        this.connections[index].inUse = false
    ..
      this.connectionLock.unlock()
    ..
..

Client.start(request Request) !$Exchange:
    # SAFETY: acquire returns an occupied connection index and every raw buffer
    # allocation is paired with its recorded capacity and failure cleanup.
    unsafe:
    if this.active == false:
        throw errors.invalidArgument("HTTP client is closed")
    ..
    parsed := try parseUrl(request.url)
    defer parsed.free()
    
    connectionIndex := try this.acquire(parsed.host, parsed.service, parsed.secure)
    onerror this.release(connectionIndex, false)

    transport := addrof this.connections[connectionIndex].socket
    requestBytes := try buildRequest(request, addrof parsed)
    onerror requestBytes.free()

    nativePoller := try poll.new(this.allocator, 1)
    onerror nativePoller.close()

    try nativePoller.add(transport, 0, poll.WRITE)
    events poll.Event* = try this.allocator.allocT[poll.Event](1)
    onerror this.allocator.free(events)

    initial := this.options.readBufferBytes
    if initial > this.options.maxResponseBytes:
        initial = this.options.maxResponseBytes
    ..
    received u8* = try this.allocator.allocT[u8](initial)
    exchange Exchange
    exchange.allocator = this.allocator
    exchange.client = this
    exchange.connection = connectionIndex
    exchange.socket = transport
    exchange.poller = move nativePoller
    exchange.events = events
    exchange.request = move requestBytes
    exchange.sent = 0
    exchange.received = received
    exchange.receivedCount = 0
    exchange.receivedCapacity = initial
    exchange.maxResponseBytes = this.options.maxResponseBytes
    exchange.readBufferBytes = this.options.readBufferBytes
    exchange.headerEnd = 0
    exchange.expectedTotal = 0
    exchange.chunked = false
    exchange.closeDelimited = false
    exchange.complete = false
    exchange.active = true
      ret exchange
    ..
..

Exchange.desiredEvents() u32:
    # SAFETY: an active Exchange retains a valid occupied client connection.
    unsafe:
    connection Connection* = addrof this.client.connections[this.connection]
    if connection.secure && connection.tls.handshaken == false:
        if connection.tls.want == tls.WANT_READ:
            ret poll.READ
        ..
        ret poll.WRITE
    ..
    if this.sent < this.request.countBytes():
        if connection.secure && connection.tls.want == tls.WANT_READ:
            ret poll.READ
        ..
        ret poll.WRITE
    ..
    if connection.secure && connection.tls.want == tls.WANT_WRITE:
        ret poll.WRITE
    ..
      ret poll.READ
    ..
..

Exchange.transportSend(bytes str) !u64:
    # SAFETY: an active exchange holds an in-use connection index below the
    # client's fixed connectionCapacity until release.
    unsafe:
        connection Connection* = addrof this.client.connections[this.connection]
        if connection.secure:
            ret try connection.tls.send(bytes)
        ..
        ret try this.socket.send(bytes)
    ..
..

Exchange.transportRecv(buffer u8[], count u64) !u64:
    # SAFETY: an active exchange holds an in-use connection index below the
    # client's fixed connectionCapacity until release.
    unsafe:
        connection Connection* = addrof this.client.connections[this.connection]
        if connection.secure:
            ret try connection.tls.recv(buffer, count)
        ..
        ret try this.socket.recv(buffer, count)
    ..
..

eventSlice(event poll.Event*) poll.Event[]:
    ret slices.fromPtr(event, 1)
..

Exchange.grow() !void:
    if this.receivedCount == this.maxResponseBytes:
        throw errors.wouldOverflow("HTTP response exceeds configured limit")
    ..
    next := this.receivedCapacity * 2
    if next < this.receivedCapacity || next > this.maxResponseBytes:
        next = this.maxResponseBytes
    ..
    this.received = try this.allocator.reallocT[u8](this.received, next)
    this.receivedCapacity = next
..

lowerAscii(value u8) u8:
    if value >= 65 && value <= 90:
        ret value + 32
    ..
    ret value
..

matchesAscii(bytes u8*, start u64, end u64, text str) bool:
    # SAFETY: callers provide start <= end within their live byte buffer; the
    # length equality bounds start+i below end.
    unsafe:
    if end - start != text.countBytes():
        ret false
    ..
    for i u64 = 0 to text.countBytes():
        if lowerAscii(bytes[start + i]) != lowerAscii(strings.byteAt(text, i)):
            ret false
        ..
    ..
      ret true
    ..
..

containsAscii(bytes u8*, start u64, end u64, text str) bool:
    if text.countBytes() > end - start:
        ret false
    ..
    i := start
    loop i + text.countBytes() <= end:
        if matchesAscii(bytes, i, i + text.countBytes(), text):
            ret true
        ..
        i = i + 1
    ..
    ret false
..

hexDigit(value u8) !u64:
    if value >= 48 && value <= 57:
        ret value - 48
    elif lowerAscii(value) >= 97 && lowerAscii(value) <= 102:
        ret lowerAscii(value) - 87
    ..
    throw errors.failure("invalid HTTP chunk size")
..

ChunkScan(
    complete bool
    decodedBytes u64
)

scanChunks(bytes u8*, start u64, count u64) !ChunkScan:
    # SAFETY: bytes spans count bytes; every lookahead and chunk payload is
    # guarded against count before access.
    unsafe:
    position := start
    decoded u64 = 0
    loop position < count:
        lineEnd := position
        loop lineEnd + 1 < count && (bytes[lineEnd] != 13 || bytes[lineEnd + 1] != 10):
            lineEnd = lineEnd + 1
        ..
        if lineEnd + 1 >= count:
            ret ChunkScan(complete=false, decodedBytes=decoded)
        ..
        size u64 = 0
        i := position
        digits u64 = 0
        loop i < lineEnd && bytes[i] != 59:
            digit := try hexDigit(bytes[i])
            if size > 0x0FFFFFFFFFFFFFFF:
                throw errors.wouldOverflow("HTTP chunk size overflow")
            ..
            size = size * 16 + digit
            digits = digits + 1
            i = i + 1
        ..
        if digits == 0:
            throw errors.failure("empty HTTP chunk size")
        ..
        position = lineEnd + 2
        if size == 0:
            # The empty trailer section is CRLF. Non-empty trailers terminate
            # at the next CRLFCRLF sequence.
            if position + 1 < count && bytes[position] == 13 && bytes[position + 1] == 10:
                ret ChunkScan(complete=true, decodedBytes=decoded)
            ..
            trailerEnd := findHeaderEnd(cast.reinterpret[u8](cast.utop(cast.ptou(bytes) + position)), count - position)
            if trailerEnd == 0:
                ret ChunkScan(complete=false, decodedBytes=decoded)
            ..
            ret ChunkScan(complete=true, decodedBytes=decoded)
        ..
        if size > count - position:
            ret ChunkScan(complete=false, decodedBytes=decoded)
        ..
        afterPayload := try checked.uAdd(position, size)
        afterChunk := try checked.uAdd(afterPayload, 2)
        if afterChunk > count:
            ret ChunkScan(complete=false, decodedBytes=decoded)
        ..
        if bytes[position + size] != 13 || bytes[position + size + 1] != 10:
            throw errors.failure("invalid HTTP chunk terminator")
        ..
        decoded = try checked.uAdd(decoded, size)
        position = afterChunk
    ..
      ret ChunkScan(complete=false, decodedBytes=decoded)
    ..
..

Exchange.updateFraming() !bool:
    # SAFETY: received spans receivedCapacity and receivedCount never exceeds
    # it; header/chunk scanners validate all computed offsets.
    unsafe:
    if this.headerEnd == 0:
        end := findHeaderEnd(this.received, this.receivedCount)
        if end == 0:
            ret false
        ..
        this.headerEnd = end
        status := try parseStatus(this.received, end)
        lineStart u64 = 0
        loop lineStart + 1 < end && (this.received[lineStart] != 13 || this.received[lineStart + 1] != 10):
            lineStart = lineStart + 1
        ..
        lineStart = lineStart + 2
        hasLength bool = false
        contentLength u64 = 0
        loop lineStart + 1 < end:
            lineEnd := lineStart
            loop lineEnd + 1 < end && (this.received[lineEnd] != 13 || this.received[lineEnd + 1] != 10):
                lineEnd = lineEnd + 1
            ..
            if lineEnd == lineStart:
                break
            ..
            colon := lineStart
            loop colon < lineEnd && this.received[colon] != 58:
                colon = colon + 1
            ..
            valueStart := colon + 1
            loop valueStart < lineEnd && (this.received[valueStart] == 32 || this.received[valueStart] == 9):
                valueStart = valueStart + 1
            ..
            if colon < lineEnd && matchesAscii(this.received, lineStart, colon, "content-length"):
                hasLength = true
                for i := valueStart to lineEnd:
                    if this.received[i] < 48 || this.received[i] > 57:
                        throw errors.failure("invalid HTTP Content-Length")
                    ..
                    tmp := try checked.uMul(contentLength, 10)
                    tmp2 := try checked.uAdd(tmp, this.received[i])
                    contentLength = try checked.uSub(tmp2, 48)
                ..
            elif colon < lineEnd && matchesAscii(this.received, lineStart, colon, "transfer-encoding") && containsAscii(this.received, valueStart, lineEnd, "chunked"):
                this.chunked = true
            elif colon < lineEnd && matchesAscii(this.received, lineStart, colon, "connection") && containsAscii(this.received, valueStart, lineEnd, "close"):
                this.closeDelimited = true
            ..
            lineStart = lineEnd + 2
        ..
        if status < 200 || status == 204 || status == 304:
            this.expectedTotal = end
        elif this.chunked == false && hasLength:
            if end > this.maxResponseBytes || contentLength > this.maxResponseBytes - end:
                throw errors.wouldOverflow("HTTP response exceeds configured limit")
            ..
            this.expectedTotal = try checked.uAdd(end, contentLength)
        elif this.chunked == false:
            this.closeDelimited = true
        ..
    ..
    if this.expectedTotal != 0 && this.receivedCount >= this.expectedTotal:
        this.complete = true
    elif this.chunked:
        scan := try scanChunks(this.received, this.headerEnd, this.receivedCount)
        this.complete = scan.complete
    ..
      ret this.complete
    ..
..

# Advances one readiness cycle and completes at the HTTP message boundary,
# leaving a keep-alive socket open in the owning client.
Exchange.poll(timeoutMs i64) !bool:
    # SAFETY: an active exchange owns capacity-tracked request/response/event
    # buffers and a valid occupied client connection for this polling cycle.
    unsafe:
    if this.active == false:
        throw errors.invalidArgument("HTTP exchange is closed")
    ..
    if this.complete:
        ret true
    ..
    connection Connection* = addrof this.client.connections[this.connection]
    transferReady bool = true
    if connection.secure && connection.tls.handshaken == false:
        if try connection.tls.handshake() == false:
            try this.poller.modify(this.socket, 0, this.desiredEvents())
            transferReady = false
        else:
            try this.poller.modify(this.socket, 0, poll.WRITE)
        ..
    ..
    # Optimistic I/O avoids an unnecessary kernel wait when a connected socket
    # can make progress immediately (and avoids relying on synthetic WRITE
    # readiness from WSAPoll after a blocking connect).
    if transferReady && this.sent < this.request.countBytes():
        remaining := this.request.countBytes() - this.sent
        requestPtr := cast.utop(cast.ptou(strings.toPtr(this.request)) + this.sent)
        view := strings.fromPtrNoCopy(requestPtr, remaining)
        written u64, writeError error = this.transportSend(view)
        if writeError.nok():
            if errors.hasCode(writeError, errors.ERR_WOULD_BLOCK) == false:
                throw writeError
            ..
        else:
            this.sent = this.sent + written
            if this.sent == this.request.countBytes():
                try this.poller.modify(this.socket, 0, poll.READ)
            ..
        ..
    ..
    if transferReady && this.sent == this.request.countBytes():
        if this.receivedCount == this.receivedCapacity:
            try this.grow()
        ..
        available := this.receivedCapacity - this.receivedCount
        receivePtr u8* = cast.reinterpret[u8](cast.utop(cast.ptou(this.received) + this.receivedCount))
        out := slices.fromPtr(receivePtr, available)
        read u64, readError error = this.transportRecv(out, available)
        if readError.nok():
            if errors.hasCode(readError, errors.ERR_WOULD_BLOCK) == false:
                throw readError
            ..
        elif read == 0 && connection.secure && connection.tls.want != tls.WANT_NONE:
            # OpenSSL reports WANT_READ/WANT_WRITE without consuming bytes.
            try this.poller.modify(this.socket, 0, this.desiredEvents())
        elif read == 0:
            if this.closeDelimited == false:
                try this.client.release(this.connection, false)
                throw errors.connectionReset("HTTP peer closed before the framed response completed")
            ..
            this.complete = true
            ret true
        else:
            this.receivedCount = this.receivedCount + read
            ret try this.updateFraming()
        ..
    ..
    try this.poller.modify(this.socket, 0, this.desiredEvents())
    count := try this.poller.wait(eventSlice(this.events), timeoutMs)
    if count == 0:
        if timeoutMs == 0:
            ret false
        ..
        throw errors.timedOut("HTTP I/O timed out")
    ..
    flags := this.events[0].flags
    if (flags & poll.ERROR) != 0:
        throw errors.failure("HTTP socket polling failed")
    ..
    if connection.secure && connection.tls.handshaken == false:
        if try connection.tls.handshake() == false:
            try this.poller.modify(this.socket, 0, this.desiredEvents())
            ret false
        ..
        try this.poller.modify(this.socket, 0, poll.WRITE)
    ..
    if this.sent < this.request.countBytes() && (flags & this.desiredEvents()) != 0:
        remaining := this.request.countBytes() - this.sent
        requestPtr := cast.utop(cast.ptou(strings.toPtr(this.request)) + this.sent)
        view := strings.fromPtrNoCopy(requestPtr, remaining)
        written := try this.transportSend(view)
        this.sent = this.sent + written
        if this.sent == this.request.countBytes():
            try this.poller.modify(this.socket, 0, poll.READ)
        ..
    ..
    if this.sent == this.request.countBytes() && ((flags & poll.READ) != 0 || (flags & poll.HANGUP) != 0):
        if this.receivedCount == this.receivedCapacity:
            try this.grow()
        ..
        available := this.receivedCapacity - this.receivedCount
        receivePtr u8* = cast.reinterpret[u8](cast.utop(cast.ptou(this.received) + this.receivedCount))
        out := slices.fromPtr(receivePtr, available)
        read u64, readError error = this.transportRecv(out, available)
        if readError.nok():
            if errors.hasCode(readError, errors.ERR_WOULD_BLOCK):
                ret false
            ..
            throw readError
        ..
        if read == 0 && connection.secure && connection.tls.want != tls.WANT_NONE:
            try this.poller.modify(this.socket, 0, this.desiredEvents())
            ret false
        ..
        if read == 0:
            if this.closeDelimited == false:
                try this.client.release(this.connection, false)
                throw errors.connectionReset("HTTP peer closed before the framed response completed")
            ..
            this.complete = true
            ret true
        ..
        this.receivedCount = this.receivedCount + read
        ret try this.updateFraming()
    ..
      ret false
    ..
..

findHeaderEnd(bytes u8*, count u64) u64:
    # SAFETY: bytes spans count and the loop proves i+3 < count.
    unsafe:
    i u64 = 0
    loop i + 3 < count:
        if bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10:
            ret i + 4
        ..
        i = i + 1
    ..
      ret 0
    ..
..

parseStatus(bytes u8*, count u64) !u16:
    # SAFETY: the minimum-count guard precedes fixed status-line byte accesses.
    unsafe:
    if count < 12 || bytes[0] != 72 || bytes[1] != 84 || bytes[2] != 84 || bytes[3] != 80 || bytes[8] != 32:
        throw errors.failure("invalid HTTP response status line")
    ..
    value u64 = 0
    for i u64 = 9 to 12:
        if bytes[i] < 48 || bytes[i] > 57:
            throw errors.failure("invalid HTTP response status")
        ..
        value = value * 10 + bytes[i] - 48
    ..
      ret cast.u64to16(value)
    ..
..

decodeChunks(bytes u8*, start u64, count u64) !$str:
    a := ctx.alloc
    # SAFETY: scanChunks validates framing within count; decodedBytes sizes the
    # destination exactly and the second pass copies only validated chunks.
    unsafe:
    scan := try scanChunks(bytes, start, count)
    if scan.complete == false:
        throw errors.failure("incomplete chunked HTTP body")
    ..
    output := try strings.alloc(scan.decodedBytes)
    destination := strings.toPtr(output)
    position := start
    written u64 = 0
    loop position < count:
        lineEnd := position
        loop bytes[lineEnd] != 13 || bytes[lineEnd + 1] != 10:
            lineEnd = lineEnd + 1
        ..
        size u64 = 0
        i := position
        loop i < lineEnd && bytes[i] != 59:
            size = size * 16 + try hexDigit(bytes[i])
            i = i + 1
        ..
        position = lineEnd + 2
        if size == 0:
            ret move output
        ..
        memory.copy(cast.utop(cast.ptou(bytes) + position), cast.utop(cast.ptou(destination) + written), size)
        written = written + size
        position = position + size + 2
    ..
      ret move output
    ..
..

Exchange.finish() !$Response:
    # SAFETY: complete framing validates all response offsets; active uniquely
    # owns the poller and buffers transferred or released on this path.
    unsafe:
    if this.active == false || this.complete == false:
        throw errors.invalidArgument("HTTP exchange is not complete")
    ..
    headerEnd := findHeaderEnd(this.received, this.receivedCount)
    if headerEnd == 0:
        throw errors.failure("HTTP response headers are incomplete")
    ..
    status := try parseStatus(this.received, headerEnd)
    raw := try strings.copy(strings.fromPtrNoCopy(this.received, headerEnd))
    onerror raw.free()
    contents str
    if this.chunked:
        contents = try decodeChunks(this.received, headerEnd, this.receivedCount)
    else:
        bodyBytes := this.receivedCount - headerEnd
        if this.expectedTotal != 0:
            bodyBytes = this.expectedTotal - headerEnd
        ..
        bodyPtr := cast.utop(cast.ptou(this.received) + headerEnd)
        contents = try strings.copy(strings.fromPtrNoCopy(bodyPtr, bodyBytes))
    ..
    try this.poller.close()
    try this.client.release(this.connection, this.closeDelimited == false)
    this.request.free()
    this.allocator.free(this.received)
    this.allocator.free(this.events)
    this.active = false
      ret Response(allocator=this.allocator, statusCode=status, rawHeaders=move raw, body=move contents, active=true)
    ..
..

# Consumes the inactive exchange wrapper after finish released its resources.
destr Exchange.releaseFinished() void:
    this.active = false
..

Client.send(request Request) !$Response:
    exchange := try this.start(request)
    onerror exchange.close()
    loop try exchange.poll(this.options.ioTimeoutMs) == false:
    ..
    response := try exchange.finish()
    exchange.releaseFinished()
    ret move response
..

runSend(task SendTask*, signal abort.Signal) !$Response:
    try signal.check()
    if task.hasExternal: try task.external.check() ..
    exchange := try task.client.start(task.request)
    onerror exchange.close()
    done bool = false
    loop done == false:
        try signal.check()
        if task.hasExternal: try task.external.check() ..
        pollMs := task.client.options.ioTimeoutMs
        if pollMs > 25: pollMs = 25 ..
        done = try exchange.poll(pollMs)
    ..
    response := try exchange.finish()
    exchange.releaseFinished()
    ret move response
..

# Runs the polling state machine on the Async worker pool and returns an awaitable response.
Client.sendAsync(request Request) !$future.Future[Response]:
    if this.active == false:
        throw errors.invalidArgument("HTTP client is closed")
    ..
    task := SendTask(client=this, request=request, external=abort.Signal(state=none), hasExternal=false)
    ret try future.newAbort[Response, SendTask](ctx.exec, runSend, task)
..

# Starts an asynchronous exchange that also observes a caller-owned signal.
Client.sendAsyncAbort(request Request, signal abort.Signal) !$future.Future[Response]:
    if this.active == false:
        throw errors.invalidArgument("HTTP client is closed")
    ..
    task := SendTask(client=this, request=request, external=signal, hasExternal=true)
    ret try future.newAbort[Response, SendTask](ctx.exec, runSend, task)
..

destr Exchange.close() !void:
    if this.active:
        try this.poller.close()
        try this.client.release(this.connection, false)
        this.request.free()
        this.allocator.free(this.received)
        this.allocator.free(this.events)
        this.active = false
    ..
..

destr Response.close() void:
    if this.active:
        this.rawHeaders.free()
        this.body.free()
        this.active = false
    ..
..

destr Client.close() !void:
    # SAFETY: connections has connectionCapacity slots; active is their
    # ownership bit and each live connection is closed and cleared once.
    unsafe:
    if this.active:
        for i u64 = 0 to this.connectionCapacity:
            connection Connection* = addrof this.connections[i]
            if connection.active:
                if connection.secure && connection.tls.active:
                    try connection.tls.close()
                ..
                try connection.socket.close()
                connection.host.free()
                connection.service.free()
                connection.active = false
            ..
        ..
        this.allocator.free(this.connections)
        try this.resolver.close()
        try this.tlsContext.close()
        this.connections = none
        this.active = false
      ..
    ..
..
