mod make_absolute

use "std:path" path
use "std:fs" fs
use "std:strings" strgs

use "shared/global" gl

pub makeAbsolute(inPath str, fromDir str) !$str:
    tmpPath $str = try strgs.copy(inPath)

    if true:
        onerror tmpPath.free()

        extension := try path.extension(tmpPath)
        defer extension.free()

        if extension != ".mg":
            if extension == "": # allows empty exts to be infered as magma files
                tmp2 := try strgs.concat(tmpPath, ".mg")
                tmpPath.free()
                tmpPath = move tmp2
            else:
                throw "invalid extension"
            ..
        ..
    ..

    # fast path, path is already absolute (unlikely)
    if testPath(tmpPath):
        ret move tmpPath
    ..

    # if not absolute, we need to consider cwd and fromDir

    parts := array str[3](gl.cwd, fromDir, tmpPath)

    baseDir $str = try path.join(parts)
    onerror baseDir.free()

    tmpPath.free()
    
    if testPath(baseDir):
        ret move baseDir
    ..

    if not path.isAbsolute(baseDir):
        if not path.isAbsolute(gl.cwd):
            throw "cwd is not absolute"
        ..
        throw "failed to generate absolute path from relative dir"
    ..
    throw "failed ot generate path"
..

testPath(p str) bool:
    m, e := fs.metadata(p)
    if e.ok() && m.kind().isFile():
        ret true
    ..
    ret false
..