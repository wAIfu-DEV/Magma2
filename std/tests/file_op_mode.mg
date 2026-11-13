mod main
use "std:errors" as errors
use "std:file_op_mode" as mode
pub main() !void:
    value := mode.OpenMode(bits=0)
    if value.bits != 0:
        throw errors.invalidArgument("empty file mode has flags set")
    ..

    readable := value.read()
    if (readable.bits & mode.FLAG_READ) == 0 || (readable.bits & mode.FLAG_WRITE) != 0:
        throw errors.invalidArgument("read mode flags are invalid")
    ..

    configured := readable.append().create().truncate()
    if (configured.bits & mode.FLAG_READ) == 0 || (configured.bits & mode.FLAG_WRITE) == 0 || (configured.bits & mode.FLAG_APPEND) == 0 || (configured.bits & mode.FLAG_CREATE) == 0 || (configured.bits & mode.FLAG_TRUNCATE) == 0:
        throw errors.invalidArgument("composed file mode flags are invalid")
    ..
..
