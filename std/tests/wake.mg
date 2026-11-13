mod main

use "std:errors" as errors
use "std:wake" as wake
use "std:footgun" as footgun

check(strategy u8) !void:
    signal := try wake.new(strategy)
    try signal.notify()
    try signal.wait()
    try signal.free()
..

pub main() !void:
    if wake.condition() == wake.semaphore():
        throw errors.failure("wake strategies are not distinct")
    ..
    try check(wake.condition())
    try check(wake.semaphore())

    invalid wake.Wake, invalidErr error = wake.new(255)
    if invalidErr.ok():
        footgun.drop[wake.Wake](move invalid)
        throw errors.failure("wake accepted an invalid strategy")
    ..
    if invalidErr.code() != 2:
        throw errors.failure("wake returned the wrong invalid-strategy error")
    ..
..
