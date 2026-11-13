mod net_tls_impl_linux
# OpenSSL 3 client backend. OpenSSL objects are opaque C pointers.

use "std:allocator" as allocator
use "std:c" as c
use "std:cast" as cast
use "std:errors" as errors
use "std:net/socket" as socket
use "std:slices" as slices
use "std:strings" as strings

link ":libssl.so.3"
link ":libcrypto.so.3"

pub Result(
    count u64
    want u8
    complete bool
)

ext ext_TLS_client_method TLS_client_method() ptr
ext ext_SSL_CTX_new SSL_CTX_new(method ptr) ptr
ext ext_SSL_CTX_free SSL_CTX_free(context ptr) void
ext ext_SSL_CTX_set_verify SSL_CTX_set_verify(context ptr, mode c.int, callback ptr) void
ext ext_SSL_CTX_set_default_verify_paths SSL_CTX_set_default_verify_paths(context ptr) c.int
ext ext_SSL_CTX_ctrl SSL_CTX_ctrl(context ptr, command c.int, larg c.long, parg ptr) c.long
ext ext_SSL_new SSL_new(context ptr) ptr
ext ext_SSL_free SSL_free(session ptr) void
ext ext_SSL_set_fd SSL_set_fd(session ptr, fd c.int) c.int
ext ext_SSL_ctrl SSL_ctrl(session ptr, command c.int, larg c.long, parg ptr) c.long
ext ext_SSL_set1_host SSL_set1_host(session ptr, host u8*) c.int
ext ext_SSL_get0_param SSL_get0_param(session ptr) ptr
ext ext_X509_VERIFY_PARAM_set1_ip_asc X509_VERIFY_PARAM_set1_ip_asc(parameter ptr, ip u8*) c.int
ext ext_SSL_connect SSL_connect(session ptr) c.int
ext ext_SSL_get_error SSL_get_error(session ptr, result c.int) c.int
ext ext_SSL_write_ex SSL_write_ex(session ptr, data ptr, length c.size_t, written c.size_t*) c.int
ext ext_SSL_read_ex SSL_read_ex(session ptr, data ptr, length c.size_t, read c.size_t*) c.int
ext ext_SSL_shutdown SSL_shutdown(session ptr) c.int

const SSL_VERIFY_PEER i32 = 1
const SSL_CTRL_SET_TLSEXT_HOSTNAME i32 = 55
const TLSEXT_NAMETYPE_host_name i64 = 0
const SSL_ERROR_WANT_READ i32 = 2
const SSL_ERROR_WANT_WRITE i32 = 3
const SSL_ERROR_ZERO_RETURN i32 = 6
const SSL_CTRL_SET_SESS_CACHE_MODE i32 = 44
const SSL_SESS_CACHE_CLIENT i64 = 1

pub closedContextError() error:
    ret errors.invalidArgument("TLS context is closed")
..

pub newContext() !ptr:
    method := ext_TLS_client_method()
    if method == none:
        throw errors.failure("OpenSSL TLS client method is unavailable")
    ..
    context := ext_SSL_CTX_new(method)
    if context == none:
        throw errors.failure("OpenSSL TLS context creation failed")
    ..
    ext_SSL_CTX_set_verify(context, SSL_VERIFY_PEER, none)
    ext_SSL_CTX_ctrl(context, SSL_CTRL_SET_SESS_CACHE_MODE, SSL_SESS_CACHE_CLIENT, none)
    if ext_SSL_CTX_set_default_verify_paths(context) != 1:
        ext_SSL_CTX_free(context)
        throw errors.failure("OpenSSL default trust store is unavailable")
    ..
    ret context
..

pub open(context ptr, transport socket.Socket*, host str) !ptr:
    a := ctx.alloc
    session := ext_SSL_new(context)
    if session == none:
        throw errors.failure("OpenSSL TLS session creation failed")
    ..
    cHost := try strings.toCstr(host)
    defer a.free(cHost)
    fd := cast.i64to32(cast.utoi(cast.ptou(try transport.nativeHandle())))
    if ext_SSL_set_fd(session, fd) != 1:
        ext_SSL_free(session)
        throw errors.failure("OpenSSL could not attach the socket")
    ..
    parameter := ext_SSL_get0_param(session)
    if ext_X509_VERIFY_PARAM_set1_ip_asc(parameter, cHost) != 1:
        if ext_SSL_ctrl(session, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, cHost) != 1:
            ext_SSL_free(session)
            throw errors.failure("OpenSSL could not configure SNI")
        ..
        if ext_SSL_set1_host(session, cHost) != 1:
            ext_SSL_free(session)
            throw errors.failure("OpenSSL could not configure hostname verification")
        ..
    ..
    ret session
..

resultError(session ptr, result i32, operation str) !Result:
    kind := ext_SSL_get_error(session, result)
    if kind == SSL_ERROR_WANT_READ:
        ret Result(count=0, want=1, complete=false)
    elif kind == SSL_ERROR_WANT_WRITE:
        ret Result(count=0, want=2, complete=false)
    elif kind == SSL_ERROR_ZERO_RETURN:
        ret Result(count=0, want=0, complete=true)
    ..
    throw errors.failure(operation)
..

pub handshake(session ptr) !Result:
    result := ext_SSL_connect(session)
    if result == 1:
        ret Result(count=0, want=0, complete=true)
    ..
    ret try resultError(session, result, "TLS handshake failed")
..

pub send(session ptr, bytes str) !Result:
    written c.size_t = 0
    result := ext_SSL_write_ex(session, strings.toPtr(bytes), bytes.countBytes(), addrof written)
    if result == 1:
        ret Result(count=written, want=0, complete=true)
    ..
    ret try resultError(session, result, "TLS write failed")
..

pub recv(session ptr, buffer u8[], count u64) !Result:
    received c.size_t = 0
    result := ext_SSL_read_ex(session, slices.toPtr(buffer), count, addrof received)
    if result == 1:
        ret Result(count=received, want=0, complete=true)
    ..
    ret try resultError(session, result, "TLS read failed")
..

pub close(session ptr) !void:
    # close_notify is best effort; Client.close owns the underlying socket.
    ext_SSL_shutdown(session)
    ext_SSL_free(session)
..

pub closeContext(context ptr) !void:
    ext_SSL_CTX_free(context)
..
