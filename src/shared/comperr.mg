mod comperr

use "std:errors" errs
use "std:writer" wr
use "std:fmt" fmt
use "std:cast" cast
use "std:strings" strgs

use "origin" origin
use "global" gl
use "filectx" fctx

pub enum Severity u8(
    INFO,
    WARNING,
    ERROR,
    _END,
)

global SevToRepr := array str[Severity._END](
    Severity.INFO="INFO"
    Severity.WARNING="WARN"
    Severity.ERROR="ERROR"
)

pub CompErr(
    file fctx.FileCtx*
    org origin.Origin
    code str
    msg str
    help str
    sev Severity
)

writeFileLine(w wr.Writer, f fctx.FileCtx*, lnIdx i64) !void:
    if lnIdx < 0:
        ret
    ..
    i := cast.itou(lnIdx)

    bound := f.lineIdx.count()
    if i >= bound || i+1 >= bound:
        ret
    ..

    lineStartIdx := try f.lineIdx.get(i)
    lineEndIdx := try f.lineIdx.get(i+1)

    length := lineEndIdx - lineStartIdx - 1
    if lineStartIdx == lineEndIdx || lineStartIdx+1 == lineEndIdx:
        length = 0
    ..

    # get view of file contents
    # TODO: add strings.view for borrowing substrings
    contentPtr := strgs.toPtr(f.content)
    contentPtr = cast.reinterpret[u8](cast.utop(cast.ptou(contentPtr) + lineStartIdx)) # TODO: make this less unbearable
    content := strgs.fromPtrNoCopy(contentPtr, length)

    w.writeInt64(lnIdx+1)
    w.write("| ")

    if content.countBytes() > 0:
        w.writeLn(content)
    else:
        w.writeLn("")
    ..
..

CompErr.writeTo(w wr.Writer) !void:
    w.write(this.file.path)
    w.write(":l")
    w.writeUint64(this.org.position.line+1)
    w.write(":c")
    w.writeUint64(this.org.position.column+1)
    w.write(" [")
    w.write(this.code)
    w.write("] ")
    w.writeLn(this.msg)

    try writeFileLine(w, this.file, this.org.position.line - 1)
    try writeFileLine(w, this.file, this.org.position.line)
    try writeFileLine(w, this.file, this.org.position.line + 1)

    if this.help != "":
        w.write("help: ")
        w.writeLn(this.help)
    ..
    w.writeLn("")
..

CompErr.log() void:
    this.writeTo(gl.logger.writer)
..
