mod main

use "std:websocket" as websocket
use "std:errors" as errors
use "std:reader" as reader
use "std:slices" as slices
use "std:writer" as writer

# Compile-time coverage for Client's generic byte-stream adapters.
checkInterfaces(client websocket.Client*) !void:
    input reader.Reader = client.reader()
    output writer.Writer = client.writer()
    try client.write("")
..

pub main() !void:
    options := websocket.defaultOptions()
    if options.maxHeaderBytes == 0 || options.maxMessageBytes == 0:
        throw errors.failure("default WebSocket limits are invalid")
    ..
    headers websocket.Header[] = slices.fromPtr(none, 0)
    client websocket.Client, failure error = websocket.connect("http://invalid", headers, options)
    if failure.ok():
        client.close()
        throw errors.failure("WebSocket accepted a non-WebSocket URL")
    ..
..
