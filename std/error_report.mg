mod error_report

use "std:cast" as cast
use "std:errors" as errors

ext ext_error_printf printf(format u8*, a u64, b u64, c u64, d u64, e u64, f u64) i32

# Prints recorded propagation sites without allocating.
# @complexity O(N), where N is the retained trace length
pub noctx printTrace(e error) void:
    cursor := errors.trace(e)
    loop cursor.isEmpty() == false:
        function := cursor.function()
        file := cursor.file()
        format := "  at %.*s (%.*s:%u:%u)\n"
        ext_error_printf(format.__data, function.__byteCount, cast.ptou(function.__data), file.__byteCount, cast.ptou(file.__data), cast.u32to64(cursor.line()), cast.u32to64(cursor.column()))
        cursor = cursor.next()
    ..
    if cursor.isTruncated():
        warning := "  ... trace truncated: diagnostic storage was reused or traversal reached its bound\n"
        ext_error_printf(warning.__data, 0, 0, 0, 0, 0, 0)
    ..
..

# Prints an uncaught error and its propagation trace without requiring an
# initialized Magma context.
pub noctx printUncaught(e error) void:
    name := errors.toStr(e)
    format := "Uncaught Error: %.*s (%.*s)\n"
    ext_error_printf(format.__data, name.__byteCount, cast.ptou(name.__data), cast.u16to64(e.__messageLength), cast.ptou(e.__message), 0, 0)
    printTrace(e)
..
