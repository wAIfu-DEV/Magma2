mod net_tls_unsupported

use "std:allocator" as allocator
use "std:errors" as errors
use "std:net/socket" as socket

pub Result(count u64, want u8, complete bool)

pub closedContextError() error:
    ret errors.invalidArgument("TLS context is closed")
..

pub newContext() !ptr:
    throw errors.failure("portable HTTPS is not implemented for this platform")
    ret none
..

pub open(context ptr, transport socket.Socket*, host str) !ptr:
    a := ctx.alloc
    throw errors.failure("portable HTTPS is not implemented for this platform")
..

pub handshake(session ptr) !Result:
    throw errors.failure("portable HTTPS is not implemented for this platform")
..

pub send(session ptr, bytes str) !Result:
    throw errors.failure("portable HTTPS is not implemented for this platform")
..

pub recv(session ptr, buffer u8[], count u64) !Result:
    throw errors.failure("portable HTTPS is not implemented for this platform")
..

pub close(session ptr) !void:
..

pub closeContext(context ptr) !void:
..
