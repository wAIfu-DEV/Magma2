mod main

use "std:http" as http
use "std:slices" as slices
use "std:heap" as heap
use "std:errors" as errors

pub main() !void:
    options := http.defaultOptions()
    if options.ioTimeoutMs == 0:
        throw errors.failure("default HTTP timeout is zero")
    ..
    headers http.Header[] = slices.fromPtr(none, 0)
    request := http.noBody("GET", "https://example.com/", headers)
    if request.bodyLength != 0:
        throw errors.failure("empty HTTP request has a body")
    ..
    a := heap.allocator()
    client := try http.new(options)
    invalidRequest := http.noBody("GET", "://", headers)
    failedResponse http.Response, sendErr error = client.send(invalidRequest)
    if sendErr.ok():
        failedResponse.close()
        client.close()
        throw errors.failure("HTTP send accepted an invalid URL")
    ..
    client.close()
..
