mod net_tls_impl_win
# Nonblocking SChannel/SSPI TLS client backend.

link "secur32"

use "std:allocator" as allocator
use "std:cast" as cast
use "std:errors" as errors
use "std:heap" as heap
use "std:memory" as memory
use "std:net/socket" as socket
use "std:slices" as slices
use "std:strings" as strings
use "std:utf8" as utf8

Handle(lower ptr, upper ptr)
Timestamp(low u32, high i32)
SecBuffer(count u32, kind u32, data ptr)
SecBufferDesc(version u32, count u32, buffers SecBuffer*)
StreamSizes(header u32, trailer u32, maximum u32, buffers u32, block u32)
SchannelCred(
    version u32
    credentialCount u32
    credentials ptr
    rootStore ptr
    mapperCount u32
    mappers ptr
    supportedAlgorithmCount u32
    supportedAlgorithms ptr
    enabledProtocols u32
    minimumCipherStrength u32
    maximumCipherStrength u32
    sessionLifespan u32
    flags u32
    credentialFormat u32
)

ContextState(
    credential Handle
)

SessionState(
    allocator allocator.Allocator
    transport socket.Socket*
    credential Handle*
    context Handle
    contextInitialized bool
    securityReady bool
    handshakeNeedsRead bool
    target u16*
    targetCount u64
    incoming u8*
    incomingCount u64
    incomingCapacity u64
    plaintext u8*
    plaintextOffset u64
    plaintextCount u64
    plaintextCapacity u64
    outgoing u8*
    outgoingOffset u64
    outgoingCount u64
    outgoingCapacity u64
    sizes StreamSizes
)

pub Result(count u64, want u8, complete bool)

ext ext_AcquireCredentialsHandleW AcquireCredentialsHandleW(principal ptr, package u16*, credentialUse u32, logon ptr, auth ptr, getKey ptr, getKeyArg ptr, credential Handle*, expiry Timestamp*) i32
ext ext_FreeCredentialsHandle FreeCredentialsHandle(credential Handle*) i32
ext ext_InitializeSecurityContextW InitializeSecurityContextW(credential Handle*, oldContext Handle*, target u16*, reqFlags u32, reserved1 u32, representation u32, input SecBufferDesc*, reserved2 u32, newHandle Handle*, output SecBufferDesc*, attributes u32*, expiry Timestamp*) i32
ext ext_DeleteSecurityContext DeleteSecurityContext(context Handle*) i32
ext ext_FreeContextBuffer FreeContextBuffer(buffer ptr) i32
ext ext_QueryContextAttributesW QueryContextAttributesW(context Handle*, attribute u32, buffer ptr) i32
ext ext_EncryptMessage EncryptMessage(context Handle*, quality u32, message SecBufferDesc*, sequence u32) i32
ext ext_DecryptMessage DecryptMessage(context Handle*, message SecBufferDesc*, sequence u32, quality u32*) i32

const SEC_E_OK i32 = 0
const SEC_I_CONTINUE_NEEDED i32 = 0x00090312
const SEC_I_CONTEXT_EXPIRED i32 = 0x00090317
const SEC_E_INCOMPLETE_MESSAGE i32 = 0x80090318
const SEC_I_RENEGOTIATE i32 = 0x00090321

const SECPKG_CRED_OUTBOUND u32 = 2
const SCHANNEL_CRED_VERSION u32 = 4
const SCH_CRED_NO_DEFAULT_CREDS u32 = 0x10
const SCH_CRED_AUTO_CRED_VALIDATION u32 = 0x20
const SECURITY_NATIVE_DREP u32 = 0x10
const SECBUFFER_VERSION u32 = 0
const SECBUFFER_EMPTY u32 = 0
const SECBUFFER_DATA u32 = 1
const SECBUFFER_TOKEN u32 = 2
const SECBUFFER_EXTRA u32 = 5
const SECBUFFER_STREAM_TRAILER u32 = 6
const SECBUFFER_STREAM_HEADER u32 = 7
const SECPKG_ATTR_STREAM_SIZES u32 = 4

const ISC_REQ_REPLAY_DETECT u32 = 0x00000004
const ISC_REQ_SEQUENCE_DETECT u32 = 0x00000008
const ISC_REQ_CONFIDENTIALITY u32 = 0x00000010
const ISC_REQ_ALLOCATE_MEMORY u32 = 0x00000100
const ISC_REQ_STREAM u32 = 0x00008000
const ISC_REQ_EXTENDED_ERROR u32 = 0x00004000

requirements() u32:
    ret ISC_REQ_REPLAY_DETECT | ISC_REQ_SEQUENCE_DETECT | ISC_REQ_CONFIDENTIALITY | ISC_REQ_ALLOCATE_MEMORY | ISC_REQ_STREAM | ISC_REQ_EXTENDED_ERROR
..

failed(status i32) bool:
    ret status < 0
..

statusError(status i32, message str) error:
    ret errors.native(cast.u64to32(cast.itou(cast.i32to64(status))), message)
..

pub closedContextError() error:
    ret errors.invalidArgument("TLS context is closed")
..

pub newContext() !ptr:
    a := heap.allocator()
    state ContextState* = cast.reinterpret[ContextState](try a.alloc(sizeof ContextState))
    memory.zero(state, sizeof ContextState)
    package := try utf8.utf8To16NT("Schannel")
    credentials SchannelCred
    memory.zero(addrof credentials, sizeof SchannelCred)
    credentials.version = SCHANNEL_CRED_VERSION
    credentials.flags = SCH_CRED_AUTO_CRED_VALIDATION
    expiry Timestamp
    status := ext_AcquireCredentialsHandleW(none, slices.toPtr(package), SECPKG_CRED_OUTBOUND, none, addrof credentials, none, none, addrof state.credential, addrof expiry)
    slices.free(package)
    if failed(status):
        a.free(state)
        throw statusError(status, "SChannel credential acquisition failed")
    ..
    ret state
..

pub open(context ptr, a allocator.Allocator, transport socket.Socket*, host str) !ptr:
    owner ContextState* = context
    state SessionState* = cast.reinterpret[SessionState](try a.alloc(sizeof SessionState))
    memory.zero(state, sizeof SessionState)
    state.allocator = a
    state.transport = transport
    state.credential = addrof owner.credential
    target := try utf8.utf8To16NT(host)
    onerror:
        slices.free(target)
        a.free(state)
    ..
    state.target = slices.toPtr(target)
    state.targetCount = slices.count(target)
    state.incomingCapacity = 65536
    state.incoming = try a.alloc(state.incomingCapacity)
    onerror:
        a.free(state.incoming)
        a.free(state.target)
        a.free(state)
    ..
    state.outgoingCapacity = 65536
    state.outgoing = try a.alloc(state.outgoingCapacity)
    onerror:
        a.free(state.outgoing)
        a.free(state.incoming)
        a.free(state.target)
        a.free(state)
    ..
    state.plaintextCapacity = 16384
    state.plaintext = try a.alloc(state.plaintextCapacity)
    ret state
..

flush(state SessionState*) !bool:
    loop state.outgoingOffset < state.outgoingCount:
        remaining := state.outgoingCount - state.outgoingOffset
        pointer := cast.utop(cast.ptou(state.outgoing) + state.outgoingOffset)
        view := strings.fromPtrNoCopy(pointer, remaining)
        written u64, writeError error = state.transport.send(view)
        if writeError.nok():
            if errors.hasCode(writeError, errors.ERR_WOULD_BLOCK):
                ret false
            ..
            throw writeError
        ..
        if written == 0:
            ret false
        ..
        state.outgoingOffset = state.outgoingOffset + written
    ..
    state.outgoingOffset = 0
    state.outgoingCount = 0
    ret true
..

receiveEncrypted(state SessionState*) !Result:
    if state.incomingCount == state.incomingCapacity:
        throw errors.wouldOverflow("SChannel encrypted input buffer is full")
    ..
    destination := cast.reinterpret[u8](cast.utop(cast.ptou(state.incoming) + state.incomingCount))
    view := slices.fromPtr(destination, state.incomingCapacity - state.incomingCount)
    count u64, readError error = state.transport.recv(view, slices.count(view))
    if readError.nok():
        if errors.hasCode(readError, errors.ERR_WOULD_BLOCK):
            ret Result(count=0, want=1, complete=false)
        ..
        throw readError
    ..
    if count == 0:
        ret Result(count=0, want=0, complete=true)
    ..
    state.incomingCount = state.incomingCount + count
    ret Result(count=count, want=0, complete=false)
..

copyOutput(state SessionState*, output SecBuffer*) !void:
    if output.count == 0 || output.data == none:
        ret
    ..
    count := cast.u32to64(output.count)
    if count > state.outgoingCapacity:
        ext_FreeContextBuffer(output.data)
        throw errors.wouldOverflow("SChannel handshake token exceeds buffer capacity")
    ..
    memory.copy(output.data, state.outgoing, count)
    state.outgoingCount = count
    state.outgoingOffset = 0
    ext_FreeContextBuffer(output.data)
..

preserveExtra(state SessionState*, buffers SecBuffer*) void:
    if buffers[1].kind == SECBUFFER_EXTRA && buffers[1].count > 0:
        extra := cast.u32to64(buffers[1].count)
        # SChannel reports the suffix length for SECBUFFER_EXTRA; its pointer
        # is not guaranteed to be populated. The extra bytes are at the tail
        # of the caller-supplied token buffer.
        source := cast.utop(cast.ptou(state.incoming) + state.incomingCount - extra)
        memory.move(source, state.incoming, extra)
        state.incomingCount = extra
    else:
        state.incomingCount = 0
    ..
..

pub handshake(raw ptr) !Result:
    state SessionState* = raw
    if try flush(state) == false:
        ret Result(count=0, want=2, complete=false)
    ..
    if state.securityReady:
        ret Result(count=0, want=0, complete=true)
    ..
    if state.contextInitialized && (state.incomingCount == 0 || state.handshakeNeedsRead):
        received := try receiveEncrypted(state)
        if received.want != 0 || received.complete:
            ret received
        ..
        state.handshakeNeedsRead = false
    ..

    inputBuffers := [2]SecBuffer
    inputDesc SecBufferDesc
    inputPtr SecBufferDesc* = none
    if state.contextInitialized:
        inputBuffers[0] = SecBuffer(count=cast.u64to32(state.incomingCount), kind=SECBUFFER_TOKEN, data=state.incoming)
        inputBuffers[1] = SecBuffer(count=0, kind=SECBUFFER_EMPTY, data=none)
        inputDesc = SecBufferDesc(version=SECBUFFER_VERSION, count=2, buffers=slices.toPtr(inputBuffers))
        inputPtr = addrof inputDesc
    ..
    outputBuffer := [1]SecBuffer
    outputBuffer[0] = SecBuffer(count=0, kind=SECBUFFER_TOKEN, data=none)
    outputDesc := SecBufferDesc(version=SECBUFFER_VERSION, count=1, buffers=slices.toPtr(outputBuffer))
    attributes u32 = 0
    expiry Timestamp
    oldContext Handle* = none
    if state.contextInitialized:
        oldContext = addrof state.context
    ..
    status := ext_InitializeSecurityContextW(state.credential, oldContext, state.target, requirements(), 0, SECURITY_NATIVE_DREP, inputPtr, 0, addrof state.context, addrof outputDesc, addrof attributes, addrof expiry)
    if status == SEC_E_INCOMPLETE_MESSAGE:
        state.handshakeNeedsRead = true
        ret Result(count=0, want=1, complete=false)
    ..
    try copyOutput(state, addrof outputBuffer[0])
    if state.contextInitialized:
        preserveExtra(state, slices.toPtr(inputBuffers))
    else:
        state.contextInitialized = true
    ..
    if failed(status):
        throw statusError(status, "SChannel TLS handshake failed")
    ..
    if status == SEC_E_OK:
        query := ext_QueryContextAttributesW(addrof state.context, SECPKG_ATTR_STREAM_SIZES, addrof state.sizes)
        if failed(query):
            throw statusError(query, "SChannel stream-size query failed")
        ..
        needed := cast.u32to64(state.sizes.header) + cast.u32to64(state.sizes.maximum) + cast.u32to64(state.sizes.trailer)
        if needed > state.outgoingCapacity:
            throw errors.wouldOverflow("SChannel TLS record exceeds buffer capacity")
        ..
        if cast.u32to64(state.sizes.maximum) > state.plaintextCapacity:
            state.plaintext = try state.allocator.realloc(state.plaintext, cast.u32to64(state.sizes.maximum))
            state.plaintextCapacity = cast.u32to64(state.sizes.maximum)
        ..
        state.securityReady = true
    elif status != SEC_I_CONTINUE_NEEDED:
        throw statusError(status, "unexpected SChannel handshake status")
    ..
    if try flush(state) == false:
        ret Result(count=0, want=2, complete=false)
    ..
    if state.securityReady:
        ret Result(count=0, want=0, complete=true)
    ..
    ret Result(count=0, want=1, complete=false)
..

pub send(raw ptr, bytes str) !Result:
    state SessionState* = raw
    if try flush(state) == false:
        ret Result(count=0, want=2, complete=false)
    ..
    count := bytes.countBytes()
    maximum := cast.u32to64(state.sizes.maximum)
    if count > maximum:
        count = maximum
    ..
    header := cast.u32to64(state.sizes.header)
    memory.copy(strings.toPtr(bytes), cast.utop(cast.ptou(state.outgoing) + header), count)
    buffers := [4]SecBuffer
    buffers[0] = SecBuffer(count=state.sizes.header, kind=SECBUFFER_STREAM_HEADER, data=state.outgoing)
    buffers[1] = SecBuffer(count=cast.u64to32(count), kind=SECBUFFER_DATA, data=cast.utop(cast.ptou(state.outgoing) + header))
    buffers[2] = SecBuffer(count=state.sizes.trailer, kind=SECBUFFER_STREAM_TRAILER, data=cast.utop(cast.ptou(state.outgoing) + header + count))
    buffers[3] = SecBuffer(count=0, kind=SECBUFFER_EMPTY, data=none)
    descriptor := SecBufferDesc(version=SECBUFFER_VERSION, count=4, buffers=slices.toPtr(buffers))
    status := ext_EncryptMessage(addrof state.context, 0, addrof descriptor, 0)
    if failed(status):
        throw statusError(status, "SChannel TLS encryption failed")
    ..
    state.outgoingCount = cast.u32to64(buffers[0].count) + cast.u32to64(buffers[1].count) + cast.u32to64(buffers[2].count)
    state.outgoingOffset = 0
    if try flush(state) == false:
        ret Result(count=count, want=2, complete=true)
    ..
    ret Result(count=count, want=0, complete=true)
..

copyPlain(state SessionState*, destination u8[], limit u64) u64:
    available := state.plaintextCount - state.plaintextOffset
    count := limit
    if count > available:
        count = available
    ..
    memory.copy(cast.utop(cast.ptou(state.plaintext) + state.plaintextOffset), slices.toPtr(destination), count)
    state.plaintextOffset = state.plaintextOffset + count
    if state.plaintextOffset == state.plaintextCount:
        state.plaintextOffset = 0
        state.plaintextCount = 0
    ..
    ret count
..

pub recv(raw ptr, buffer u8[], count u64) !Result:
    state SessionState* = raw
    if try flush(state) == false:
        ret Result(count=0, want=2, complete=false)
    ..
    if state.plaintextCount > state.plaintextOffset:
        ret Result(count=copyPlain(state, buffer, count), want=0, complete=true)
    ..
    if state.incomingCount == 0:
        received := try receiveEncrypted(state)
        if received.want != 0 || received.complete:
            ret received
        ..
    ..
    encryptedBefore := state.incomingCount
    buffers := [4]SecBuffer
    buffers[0] = SecBuffer(count=cast.u64to32(state.incomingCount), kind=SECBUFFER_DATA, data=state.incoming)
    buffers[1] = SecBuffer(count=0, kind=SECBUFFER_EMPTY, data=none)
    buffers[2] = SecBuffer(count=0, kind=SECBUFFER_EMPTY, data=none)
    buffers[3] = SecBuffer(count=0, kind=SECBUFFER_EMPTY, data=none)
    descriptor := SecBufferDesc(version=SECBUFFER_VERSION, count=4, buffers=slices.toPtr(buffers))
    quality u32 = 0
    status := ext_DecryptMessage(addrof state.context, addrof descriptor, 0, addrof quality)
    if status == SEC_E_INCOMPLETE_MESSAGE:
        received := try receiveEncrypted(state)
        if received.complete:
            throw errors.connectionReset("TLS peer closed with an incomplete record")
        ..
        if received.want != 0:
            ret received
        ..
        ret Result(count=0, want=1, complete=false)
    elif status == SEC_I_CONTEXT_EXPIRED:
        state.incomingCount = 0
        ret Result(count=0, want=0, complete=true)
    elif status == SEC_I_RENEGOTIATE:
        throw errors.failure("SChannel TLS renegotiation is not supported")
    elif failed(status):
        throw statusError(status, "SChannel TLS decryption failed")
    ..
    data ptr = none
    dataCount u64 = 0
    extraCount u64 = 0
    for i u64 = 0 to 4:
        if buffers[i].kind == SECBUFFER_DATA:
            data = buffers[i].data
            dataCount = cast.u32to64(buffers[i].count)
        elif buffers[i].kind == SECBUFFER_EXTRA:
            extraCount = cast.u32to64(buffers[i].count)
        ..
    ..
    if dataCount > state.plaintextCapacity:
        throw errors.wouldOverflow("SChannel plaintext exceeds buffer capacity")
    ..
    if dataCount > 0:
        memory.copy(data, state.plaintext, dataCount)
        state.plaintextCount = dataCount
        state.plaintextOffset = 0
    ..
    if extraCount > 0:
        extraSource := cast.utop(cast.ptou(state.incoming) + encryptedBefore - extraCount)
        memory.move(extraSource, state.incoming, extraCount)
    ..
    state.incomingCount = extraCount
    if dataCount == 0 && encryptedBefore > 0:
        ret Result(count=0, want=1, complete=false)
    ..
    ret Result(count=copyPlain(state, buffer, count), want=0, complete=true)
..

pub close(raw ptr) !void:
    state SessionState* = raw
    if state.contextInitialized:
        ext_DeleteSecurityContext(addrof state.context)
    ..
    state.allocator.free(state.target)
    state.allocator.free(state.incoming)
    state.allocator.free(state.plaintext)
    state.allocator.free(state.outgoing)
    state.allocator.free(state)
..

pub closeContext(raw ptr) !void:
    if raw != none:
        state ContextState* = raw
        status := ext_FreeCredentialsHandle(addrof state.credential)
        heap.allocator().free(state)
        if failed(status):
            throw statusError(status, "SChannel credential release failed")
        ..
    ..
..
