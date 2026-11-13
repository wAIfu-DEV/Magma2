mod main

use "std:abort" as abort
use "std:errors" as errors
use "std:time" as time

checkSignal(signal abort.Signal) !bool:
    try signal.check()
    ret true
..

pub main() !void:
    controller := try abort.new()
    signal := controller.signal()
    controller.abort()
    if signal.isAborted() == false || signal.reason() != abort.REASON_REQUESTED:
        controller.close()
        throw errors.failure("manual abort was not published")
    ..
    checked bool, abortError error = checkSignal(signal)
    if errors.hasCode(abortError, errors.ERR_CANCELLED) == false:
        controller.close()
        throw errors.failure("manual abort returned the wrong error")
    ..
    controller.close()

    timed := try abort.new()
    timedSignal := timed.signal()
    try timed.abortAfter(5)
    loop timedSignal.isAborted() == false:
        time.sleep(1)
    ..
    timedCheck bool, timeoutError error = checkSignal(timedSignal)
    if errors.hasCode(timeoutError, errors.ERR_TIMED_OUT) == false:
        timed.close()
        throw errors.failure("deadline abort returned the wrong error")
    ..
    timed.close()
..
