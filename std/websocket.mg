mod websocket
# Blocking RFC 6455 client over TCP or TLS.

use "std:allocator" as allocator
use "std:base64" as base64
use "std:builder" as builder
use "std:cast" as cast
use "std:errors" as errors
use "std:memory" as memory
use "std:random" as random
use "std:reader" as reader
use "std:sha1" as sha1
use "std:slices" as slices
use "std:strconv" as strconv
use "std:strings" as strings
use "std:utf8" as utf8
use "std:writer" as writer
use "std:net/address" as address
use "std:net/dns" as dns
use "std:net/socket" as socket
use "std:footgun" as fg
use "std:checked" as checked

pub const MESSAGE_TEXT u8 = 1
pub const MESSAGE_BINARY u8 = 2

const OPCODE_CONTINUATION u8 = 0
const OPCODE_TEXT u8 = 1
const OPCODE_BINARY u8 = 2
const OPCODE_CLOSE u8 = 8
const OPCODE_PING u8 = 9
const OPCODE_PONG u8 = 10
const ACCEPT_GUID str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

pub Header(
    name str
    value str
)

pub Options(
    dns dns.Options
    maxHeaderBytes u64
    maxMessageBytes u64
)

pub defaultOptions() Options:
    ret Options(dns=dns.defaultOptions(), maxHeaderBytes=16384, maxMessageBytes=16 * 1024 * 1024)
..

pub Message(
    allocator allocator.Allocator
    kind u8
    data $str
    active bool
)

pub Client impl reader.Reader writer.Writer(
    allocator allocator.Allocator
    resolver dns.Resolver
    transport socket.Socket
    secure bool
    active bool
    closing bool
    maxMessageBytes u64
    readBuffer ptr
    readCount u64
    readOffset u64
    readBufferActive bool
)

ParsedUrl(
    host $str
    service $str
    target $str
    secure bool
)

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
    secure bool = false
    if schemeEnd == 3 && strings.byteAt(url, 0) == 119 && strings.byteAt(url, 1) == 115 && strings.byteAt(url, 2) == 115:
        secure = true
    elif schemeEnd != 2 || strings.byteAt(url, 0) != 119 || strings.byteAt(url, 1) != 115:
        throw errors.invalidArgument("WebSocket URL scheme must be ws or wss")
    ..
    authorityStart := schemeEnd + 3
    authorityEnd := authorityStart
    loop authorityEnd < n && strings.byteAt(url, authorityEnd) != 47 && strings.byteAt(url, authorityEnd) != 63:
        authorityEnd = authorityEnd + 1
    ..
    if authorityEnd == authorityStart:
        throw errors.invalidArgument("WebSocket URL host is empty")
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
        port := try strconv.parseUint(service)
        if port == 0 || port > 65535:
            throw errors.invalidArgument("WebSocket port is out of range")
        ..
    elif secure:
        service = try strings.copy("443")
    else:
        service = try strings.copy("80")
    ..
    onerror service.free()
    target str
    if authorityEnd == n:
        target = try strings.copy("/")
    elif strings.byteAt(url, authorityEnd) == 63:
        prefixCapacity := try checked.uAdd(n - authorityEnd, 1)
        prefix := try builder.newWithCapacity(prefixCapacity)
        defer prefix.free()
        try prefix.appendBorrowed("/")
        suffix := try strings.substring(url, authorityEnd, n)
        try prefix.appendOwned(move suffix)
        target = try prefix.build()
    else:
        target = try strings.substring(url, authorityEnd, n)
    ..
    ret ParsedUrl(host=move host, service=move service, target=move target, secure=secure)
..

destr ParsedUrl.free() void:
    this.host.free()
    this.service.free()
    this.target.free()
..

Client.sendRaw(bytes str) !u64:
    ret try this.transport.send(bytes)
..

Client.recvRaw(buffer u8[], count u64) !u64:
    ret try this.transport.recv(buffer, count)
..

writeTransportAll(client Client*, bytes str) !void:
    offset u64 = 0
    loop offset < bytes.countBytes():
        part := strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(bytes)) + offset), bytes.countBytes() - offset)
        written := try client.sendRaw(part)
        if written == 0:
            throw errors.connectionReset("WebSocket transport closed while writing")
        ..
        offset = offset + written
    ..
..

Client.readExact(buffer u8[], count u64) !void:
    if count > slices.count(buffer):
        throw errors.invalidArgument("WebSocket read buffer is too small")
    ..
    offset u64 = 0
    loop offset < count:
        view u8[] = slices.fromPtr(cast.utop(cast.ptou(slices.toPtr(buffer)) + offset), count - offset)
        received := try this.recvRaw(view, count - offset)
        if received == 0:
            throw errors.connectionReset("WebSocket transport closed while reading")
        ..
        offset = offset + received
    ..
..

makeKey() !$str:
    a := ctx.alloc
    nonce := try strings.alloc(16)
    defer nonce.free()
    view u8[] = slices.fromPtr(strings.toPtr(nonce), 16)
    try random.bytesTo(view)
    encoded := try base64.encode(view)
    ret move encoded
..

acceptFor(key str) !$str:
    a := ctx.alloc
    joinedCapacity := try checked.uAdd(key.countBytes(), ACCEPT_GUID.countBytes())
    joined := try builder.newWithCapacity(joinedCapacity)
    defer joined.free()
    try joined.appendBorrowed(key)
    try joined.appendBorrowed(ACCEPT_GUID)
    source := try joined.build()
    defer source.free()
    input u8[] = slices.fromPtr(strings.toPtr(source), source.countBytes())
    output u8[] = try sha1.sum(input)
    defer slices.free(output)
    encoded := try base64.encode(output)
    ret move encoded
..

lower(value u8) u8:
    if value >= 65 && value <= 90:
        ret value + 32
    ..
    ret value
..

equalInsensitive(left str, right str) bool:
    if left.countBytes() != right.countBytes():
        ret false
    ..
    for i u64 = 0 to left.countBytes():
        if lower(strings.byteAt(left, i)) != lower(strings.byteAt(right, i)):
            ret false
        ..
    ..
    ret true
..

trim(value str) str:
    start u64 = 0
    finish := value.countBytes()
    loop start < finish && (strings.byteAt(value, start) == 32 || strings.byteAt(value, start) == 9):
        start = start + 1
    ..
    loop finish > start && (strings.byteAt(value, finish - 1) == 32 || strings.byteAt(value, finish - 1) == 9):
        finish = finish - 1
    ..
    ret strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(value)) + start), finish - start)
..

headerValue(headers str, name str) str:
    position u64 = 0
    loop position + 1 < headers.countBytes():
        lineEnd := position
        loop lineEnd + 1 < headers.countBytes() && (strings.byteAt(headers, lineEnd) != 13 || strings.byteAt(headers, lineEnd + 1) != 10):
            lineEnd = lineEnd + 1
        ..
        colon := position
        loop colon < lineEnd && strings.byteAt(headers, colon) != 58:
            colon = colon + 1
        ..
        if colon < lineEnd:
            field := strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(headers)) + position), colon - position)
            if equalInsensitive(field, name):
                value := strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(headers)) + colon + 1), lineEnd - colon - 1)
                ret trim(value)
            ..
        ..
        position = lineEnd + 2
    ..
    ret ""
..

containsToken(value str, wanted str) bool:
    start u64 = 0
    loop start < value.countBytes():
        finish := start
        loop finish < value.countBytes() && strings.byteAt(value, finish) != 44:
            finish = finish + 1
        ..
        token := strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(value)) + start), finish - start)
        if equalInsensitive(trim(token), wanted):
            ret true
        ..
        start = finish + 1
    ..
    ret false
..

Client.readHeaders(maxBytes u64) !$str:
    output := try strings.alloc(maxBytes)
    onerror output.free()
    destination := strings.toPtr(output)
    one := [1]u8
    matched u8 = 0
    count u64 = 0
    loop true:
        view u8[] = one
        try this.readExact(view, 1)
        byte := one[0]
        if count == maxBytes:
            throw errors.wouldOverflow("WebSocket response headers exceed configured limit")
        ..
        unsafe:
            destination[count] = byte
        ..
        count = count + 1
        if (matched == 0 || matched == 2) && byte == 13:
            matched = matched + 1
        elif (matched == 1 || matched == 3) && byte == 10:
            matched = matched + 1
        else:
            matched = 0
        ..
        if matched == 4:
            ignored := strings.truncate(addrof output, count)
            ret move output
        ..
    ..
..

Client.openingHandshake(parsed ParsedUrl*, headers Header[], maxHeaderBytes u64) !void:
    a := ctx.alloc
    key := try makeKey()
    defer key.free()
    request := try builder.newWithCapacity(256)
    defer request.free()
    try request.appendBorrowed("GET ")
    try request.appendBorrowed(parsed.target)
    try request.appendBorrowed(" HTTP/1.1\r\nHost: ")
    try request.appendBorrowed(parsed.host)
    defaultPort := strings.compare(parsed.service, "80") && parsed.secure == false
    if parsed.secure:
        defaultPort = strings.compare(parsed.service, "443")
    ..
    if defaultPort == false:
        try request.appendBorrowed(":")
        try request.appendBorrowed(parsed.service)
    ..
    try request.appendBorrowed("\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ")
    try request.appendBorrowed(key)
    try request.appendBorrowed("\r\n")
    for i u64 = 0 to slices.count(headers):
        try request.appendBorrowed(headers[i].name)
        try request.appendBorrowed(": ")
        try request.appendBorrowed(headers[i].value)
        try request.appendBorrowed("\r\n")
    ..
    try request.appendBorrowed("\r\n")
    serialized := try request.build()
    defer serialized.free()
    try writeTransportAll(this, serialized)
    response := try this.readHeaders(maxHeaderBytes)
    defer response.free()
    if response.countBytes() < 12 || strings.byteAt(response, 9) != 49 || strings.byteAt(response, 10) != 48 || strings.byteAt(response, 11) != 49:
        throw errors.failure("WebSocket server rejected the opening handshake")
    ..
    if equalInsensitive(headerValue(response, "Upgrade"), "websocket") == false:
        throw errors.failure("WebSocket response has invalid Upgrade header")
    ..
    if containsToken(headerValue(response, "Connection"), "Upgrade") == false:
        throw errors.failure("WebSocket response has invalid Connection header")
    ..
    expected := try acceptFor(key)
    defer expected.free()
    if strings.compare(headerValue(response, "Sec-WebSocket-Accept"), expected) == false:
        throw errors.failure("WebSocket response has invalid accept key")
    ..
..

connectTransport(host str, service str, secure bool, options Options) !$Client:
    a := ctx.alloc
    resolver := try dns.new(a, options.dns)
    onerror resolver.close()
    endpoints := [16]address.Endpoint
    endpointView address.Endpoint[] = endpoints
    count := try resolver.resolveTo(host, service, address.FAMILY_UNSPECIFIED, endpointView)
    if count == 0:
        throw errors.notFound("WebSocket host has no addresses")
    ..
    transport := try socket.open(endpoints[0].address.family, socket.TYPE_STREAM)
    onerror transport.close()
    try transport.connect(endpoints[0])
    client Client
    memory.zero(addrof client, sizeof Client)
    client.allocator = a
    client.resolver = move resolver
    client.transport = move transport
    client.secure = secure
    client.active = true
    client.maxMessageBytes = options.maxMessageBytes
    ret client
..

pub connect(url str, headers Header[], options Options) !$Client:
    if options.maxHeaderBytes < 4 || options.maxMessageBytes == 0:
        throw errors.invalidArgument("invalid WebSocket client limits")
    ..
    parsed := try parseUrl(url)
    defer parsed.free()
    if parsed.secure:
        throw errors.failure("secure WebSocket connections are not yet supported")
    ..
    client := try connectTransport(parsed.host, parsed.service, parsed.secure, options)
    try client.openingHandshake(addrof parsed, headers, options.maxHeaderBytes)
    ret move client
..

Client.sendFrame(opcode u8, payload str) !void:
    if payload.countBytes() > this.maxMessageBytes:
        throw errors.wouldOverflow("WebSocket message exceeds configured limit")
    ..
    mask := [4]u8
    maskView u8[] = mask
    try random.bytesTo(maskView)
    header := [14]u8
    header[0] = 128 | opcode
    headerCount u64 = 2
    length := payload.countBytes()
    if length <= 125:
        header[1] = 128 | cast.u64to8(length)
    elif length <= 65535:
        header[1] = 128 | 126
        header[2] = cast.u64to8(length >> 8)
        header[3] = cast.u64to8(length)
        headerCount = 4
    else:
        header[1] = 128 | 127
        for i u64 = 0 to 8:
            bounded headerCount + i < 14:
                header[headerCount + i] = cast.u64to8(length >> cast.u64to32((7 - i) * 8))
            ..
        ..
        headerCount = 10
    ..
    for i u64 = 0 to 4:
        bounded headerCount + i < 14:
            header[headerCount + i] = mask[i]
        ..
    ..
    headerCount = headerCount + 4
    try writeTransportAll(this, strings.fromPtrNoCopy(slices.toPtr(header), headerCount))
    masked := try strings.alloc(length)
    defer masked.free()
    output := strings.toPtr(masked)
    input := strings.toPtr(payload)
    unsafe:
        for i u64 = 0 to length:
            output[i] = input[i] ^ mask[i % 4]
        ..
    ..
    try writeTransportAll(this, masked)
..

Client.sendText(message str) !void:
    if this.active == false || this.closing:
        throw errors.invalidArgument("WebSocket client is not open")
    ..
    if utf8.validate(message) == false:
        throw errors.invalidArgument("WebSocket text message is not valid UTF-8")
    ..
    try this.sendFrame(OPCODE_TEXT, message)
..

Client.sendBinary(message str) !void:
    if this.active == false || this.closing:
        throw errors.invalidArgument("WebSocket client is not open")
    ..
    try this.sendFrame(OPCODE_BINARY, message)
..

# Sends bytes as one binary WebSocket message.
# A successful write always consumes the complete input.
Client.write(bytes str) !u64:
    try this.sendBinary(bytes)
    ret bytes.countBytes()
..

# Returns a borrowed generic writer view of this client.
# The client must remain alive and unmoved while the view is used.
Client.writer() writer.Writer:
    ret this.protoBorrow[writer.Writer]()
..

Client.readPayload(length u64) !$str:
    payload := try strings.alloc(length)
    onerror payload.free()
    view u8[] = slices.fromPtr(strings.toPtr(payload), length)
    try this.readExact(view, length)
    ret move payload
..

Client.readFrame() !$Message:
    header := [2]u8
    headerView u8[] = header
    try this.readExact(headerView, 2)
    if (header[0] & 112) != 0 || (header[1] & 128) != 0:
        throw errors.failure("invalid WebSocket frame flags")
    ..
    final := (header[0] & 128) != 0
    opcode := header[0] & 15
    length u64 = header[1] & 127
    extended := [8]u8
    if length == 126:
        view u8[] = extended
        try this.readExact(view, 2)
        length = (cast.u8to64(extended[0]) << 8) | cast.u8to64(extended[1])
        if length < 126:
            throw errors.failure("non-canonical WebSocket frame length")
        ..
    elif length == 127:
        view u8[] = extended
        try this.readExact(view, 8)
        if (extended[0] & 128) != 0:
            throw errors.failure("invalid WebSocket frame length")
        ..
        length = 0
        for i u64 = 0 to 8:
            length = (length << 8) | cast.u8to64(extended[i])
        ..
        if length <= 65535:
            throw errors.failure("non-canonical WebSocket frame length")
        ..
    ..
    if length > this.maxMessageBytes:
        throw errors.wouldOverflow("WebSocket message exceeds configured limit")
    ..
    if opcode >= 8 && (final == false || length > 125):
        throw errors.failure("invalid WebSocket control frame")
    ..
    payload := try this.readPayload(length)
    if opcode == OPCODE_PING:
        try this.sendFrame(OPCODE_PONG, payload)
        payload.free()
        ret try this.readFrame()
    elif opcode == OPCODE_PONG:
        payload.free()
        ret try this.readFrame()
    elif opcode == OPCODE_CLOSE:
        if this.closing == false:
            this.closing = true
            try this.sendFrame(OPCODE_CLOSE, payload)
        ..
        payload.free()
        throw errors.endOfFile("WebSocket peer closed the connection")
    elif final == false || opcode == OPCODE_CONTINUATION:
        payload.free()
        throw errors.failure("fragmented WebSocket messages are not yet supported")
    elif opcode != OPCODE_TEXT && opcode != OPCODE_BINARY:
        payload.free()
        throw errors.failure("unknown WebSocket frame opcode")
    ..
    if opcode == OPCODE_TEXT && utf8.validate(payload) == false:
        payload.free()
        throw errors.failure("WebSocket text message is not valid UTF-8")
    ..
    kind := MESSAGE_BINARY
    if opcode == OPCODE_TEXT:
        kind = MESSAGE_TEXT
    ..
    ret Message(allocator=this.allocator, kind=kind, data=move payload, active=true)
..

Client.receive() !$Message:
    if this.active == false:
        throw errors.invalidArgument("WebSocket client is closed")
    ..
    ret try this.readFrame()
..

# Reads up to nBytes from binary or text message payloads. Unread bytes from a
# message are retained for the next call, so the generic Reader is a byte
# stream even though the WebSocket transport is message-oriented.
Client.readRaw(buff u8[], nBytes u64) !u64:
    if nBytes == 0:
        ret 0
    ..
    if this.active == false:
        throw errors.invalidArgument("WebSocket client is closed")
    ..
    loop this.readBufferActive == false:
        message := try this.readFrame()
        this.readCount = message.data.countBytes()
        this.readOffset = 0
        if this.readCount == 0:
            message.close()
        else:
            this.readBuffer = strings.toPtr(message.data)
            this.readBufferActive = true
            # Ownership of the allocation is now tracked manually by Client.
            message.active = false
            fg.drop(move message)
        ..
    ..
    available := this.readCount - this.readOffset
    count := nBytes
    if available < count:
        count = available
    ..
    source := cast.utop(cast.ptou(this.readBuffer) + this.readOffset)
    memory.copy(source, slices.toPtr(buff), count)
    this.readOffset = this.readOffset + count
    if this.readOffset == this.readCount:
        strings.fromPtrNoCopy(this.readBuffer, this.readCount).free()
        this.readBufferActive = false
        this.readBuffer = none
        this.readCount = 0
        this.readOffset = 0
    ..
    ret count
..

# Returns a borrowed generic reader view of this client.
# The client must remain alive and unmoved while the view is used.
Client.reader() reader.Reader:
    ret this.protoBorrow[reader.Reader]()
..

destr Message.close() void:
    if this.active:
        this.data.free()
        this.active = false
    ..
..

destr Client.close() !void:
    if this.readBufferActive:
        strings.fromPtrNoCopy(this.readBuffer, this.readCount).free()
        this.readBufferActive = false
        this.readBuffer = none
        this.readCount = 0
        this.readOffset = 0
    ..
    if this.active:
        this.closing = true
        try this.transport.close()
        try this.resolver.close()
        this.active = false
    ..
..
