mod main
use "std:errors" as errors
use "std:strings" as strings

tracedFailure() !u8:
    throw errors.invalidArgument("traced failure")
..

pub main() !void:
    success := errors.ok()
    errors.printTrace(success)
    if success.nok() || success.ok() == false || success.nok():
        throw errors.failure("ok error classification changed")
    ..
    failure := errors.invalidArgument("bad input")
    if errors.hasCode(failure, 2) == false || failure.nok() == false || errors.is(failure, errors.invalidArgument("other")) == false || strings.compare(failure.message(), "bad input") == false:
        throw errors.failure("error behavior changed")
    ..
    if strings.compare(errors.toStr(failure), "invalid argument") == false:
        throw errors.failure("error category string changed")
    ..
    native := errors.native(123, "native")
    if errors.isNative(native) == false || errors.nativeCode(native) != 123:
        throw errors.failure("native error behavior changed")
    ..
    if errors.failure("").code() != 1 || errors.outOfMemory("").code() != 3 || errors.endOfFile("").code() != 4 || errors.wouldOverflow("").code() != 5 || errors.invalidType("").code() != 6 || errors.outOfBounds("").code() != 7 || errors.notFound("").code() != 8 || errors.cancelled("").code() != 9:
        throw errors.failure("standard error codes changed")
    ..
    if strings.compare(errors.toStr(errors.cancelled("")), "cancelled") == false:
        throw errors.failure("cancelled error category string changed")
    ..

    ignored u8, traced error = tracedFailure()
    trace := errors.trace(traced)
    if trace.isEmpty():
        throw errors.failure("throw did not record an error trace")
    ..
    if strings.compare(trace.function(), "tracedFailure") == false || strings.compare(trace.file(), "errors.mg") == false || trace.line() != 6 || trace.column() == 0 || trace.isTruncated():
        throw errors.failure("error trace metadata changed")
    ..
    parent := trace.next()
    if parent.isEmpty() == false:
        throw errors.failure("single throw recorded an unexpected parent frame")
    ..
..
