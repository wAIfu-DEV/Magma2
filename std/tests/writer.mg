mod main
use "std:errors" as errors
use "std:cast" as cast
use "std:strings" as strings
use "std:writer" as writer
Sink impl writer.Writer(value u8)
Sink.writeRaw(bytes str) !u64:
    ret bytes.countBytes()
..

OverreportSink impl writer.Writer(value u8)
OverreportSink.writeRaw(bytes str) !u64:
    ret bytes.countBytes() + 1
..

pub main() !void:
    sink := Sink(value=0)
    output := sink.protoBorrow[writer.Writer]()
    if try output.write("ab") != 2 || try output.write("abc") != 3:
        throw errors.failure("writer write behavior changed")
    ..
    count := try output.writeLn("abc")
    if count != 4:
        throw errors.failure("writer behavior changed")
    ..
    floatCount := try output.writeFloat64(1.5, 1)
    if floatCount != 3:
        throw errors.failure("writer float behavior changed")
    ..
    negativeCount := try output.writeFloat64(-2.0, 0)
    if negativeCount != 2:
        throw errors.failure("writer negative float behavior changed")
    ..
    if try output.writeBool(true) != 4 || try output.writeBool(false) != 5:
        throw errors.failure("writer bool behavior changed")
    ..
    if try output.writeInt64(-42) != 3 || try output.writeUint64(42) != 2:
        throw errors.failure("writer integer behavior changed")
    ..

    overreport := OverreportSink(value=0)
    invalidCount u64, invalidCountError error = overreport.protoBorrow[writer.Writer]().write("x")
    if invalidCountError.ok():
        throw errors.failure("writer accepted an impossible write count")
    ..
..
