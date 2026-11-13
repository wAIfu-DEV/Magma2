mod make_absolute

use "std:path" path
use "std:fs" fs
use "std:strings" strgs

use "shared/global" gl

pub makeAbsolute(inPath str, fromDir str) !$str:
    tmpPath $str
    prefixIdx, prefixErr := strgs.find(inPath, "std:")
    if prefixErr.ok() && prefixIdx == 0:
        if gl.stdLibRoot == gl.UNSET:
            throw "standard library root is not configured"
        ..
        suffix := try strgs.trimPrefix(inPath, "std:")
        defer suffix.free()
        normalizedSuffix := try path.normalize(suffix)
        defer normalizedSuffix.free()
        if path.isAbsolute(suffix) || normalizedSuffix == "..":
            throw "standard library import escapes the std directory"
        else:
            idx, err := strgs.find(normalizedSuffix, "../")
            if err.ok():
                throw "standard library import escapes the std directory"
            ..
        ..
        parts := [2]str(gl.stdLibRoot, suffix)
        tmpPath = try path.join(parts)
    else:
        tmpPath = try strgs.copy(inPath)
    ..

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
    if path.isAbsolute(tmpPath) && testPath(tmpPath):
        ret move tmpPath
    ..

    # if not absolute, we need to consider cwd and fromDir

    parts := [3]str(gl.cwd, fromDir, tmpPath)

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
    throw "failed to generate path"
..

testPath(p str) bool:
    m, e := fs.metadata(p)
    if e.ok() && m.kind().isFile():
        ret true
    ..
    ret false
..
