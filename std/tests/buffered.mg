mod main

use "std:allocator" as allocator
use "std:buffered" as buffered
use "std:cast" as cast
use "std:errors" as errors
use "std:heap" as heap
use "std:reader" as reader
use "std:strings" as strings
use "std:writer" as writer

Sink impl writer.Writer(total u64*)

Sink.writeRaw(bytes str) !u64:
    count := bytes.countBytes()
    *this.total = *this.total + count
    ret count
..

Source impl reader.Reader(calls u64)

Source.readRaw(bytes u8[], count u64) !u64:
    if this.calls == 0 && count >= 2:
        # SAFETY: Reader supplies a slice with at least count writable elements.
        unsafe:
            bytes[0] = 65
            bytes[1] = 10
        ..
        this.calls = 1
        ret 2
    ..
    ret 0
..

pub main() !void:
    a allocator.Allocator = heap.allocator()
    written u64 = 0
    sink := Sink(total=addrof written)
    raw := sink.protoBorrow[writer.Writer]()
    output := try buffered.writerBuffered(raw)
    defer output.close()
    if try output.write("a") != 1 || try output.write("b") != 1 || try output.writeLn("c") != 2:
        throw errors.failure("buffered writer basic writes changed")
    ..
    if try output.writeBool(true) != 4 || try output.writeInt64(-2) != 2 || try output.writeUint64(3) != 1 || try output.writeFloat64(1.5, 1) != 3:
        throw errors.failure("buffered writer formatting changed")
    ..
    facade := output.writer()
    try facade.write("z")
    flushed := try output.flush()
    if flushed != 15 || written != 15:
        throw errors.failure("buffered writer flush changed")
    ..
    source := Source(calls=0)
    input := source.protoBorrow[reader.Reader]()
    bufferedInput := try buffered.readerBuffered(input)
    defer bufferedInput.close()
    if bufferedInput.filledCount() != 0 || bufferedInput.isEof():
        throw errors.failure("new buffered reader state changed")
    ..
    if try bufferedInput.fillBuffer() == false || bufferedInput.filledCount() != 2:
        throw errors.failure("buffered reader fill changed")
    ..
    line := try bufferedInput.readLn()
    defer line.free()
    linePtr u8* = strings.toPtr(line)
    # SAFETY: owned strings reserve a terminator immediately after countBytes.
    unsafe:
        if linePtr[line.countBytes()] != 0:
            throw errors.failure("buffered line is not null terminated")
        ..
    ..
    rawReader := bufferedInput.reader()
    spare := [1]u8
    if try rawReader.readToBuff(spare, 1) != 0:
        throw errors.failure("buffered reader EOF changed")
    ..
    bufferedInput.setFilled(0)
    bufferedInput.markEof()
    if bufferedInput.filledCount() != 0 || bufferedInput.isEof() == false:
        throw errors.failure("buffered reader state controls changed")
    ..
..
