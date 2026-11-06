mod open_file

use "std:fs" fs
use "std:file" file
use "std:buffered" buf
use "std:strings" strgs

use "shared/filectx" fctx

parseFirstLn(line str) !$str:
    idx, e := strgs.find(line, "mod ")
    if e.nok():
        throw "first line of .mg file must start with 'mod <module-name>'"
    ..
    modName := try strgs.trimPrefix(line, "mod ")
    defer modName.free()

    trimmed := try strgs.trim(modName)
    ret move trimmed
..

pub openFile(path str) !$fctx.FileCtx:
    f := try file.open(path, file.mode().read())
    defer f.close()

    rd := try f.reader()
    bfrd := try buf.readerBuffered(rd)
    defer bfrd.close()

    firstLn := try bfrd.readLn()
    defer firstLn.free()

    try f.seek(0, 0)

    modName := try parseFirstLn(firstLn)

    fc := try fctx.new()
    fc.path = path
    fc.modName = move modName
    fc.content = try rd.read(f.count()) # TODO: add readall util

    # register every line start idx
    newline := strgs.byteAt("\n", 0)
    fc.lineIdx.pushRight(0)
    for cIdx := 0 to fc.content.countBytes():
        if strgs.byteAt(fc.content, cIdx) == newline:
            fc.lineIdx.pushRight(cIdx+1)
        ..
    ..
    fc.lineIdx.pushRight(fc.content.countBytes())

    ret fc
..