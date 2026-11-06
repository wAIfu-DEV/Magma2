mod main

use "std:io" io
use "std:fs" fs
use "std:cast" cast

use "src/helper/logger" log
use "src/shared/token_types" tkt
use "src/shared/comperr" comperr
use "src/shared/origin" org
use "src/make_absolute" mk_abs

use "src/shared/global" gl
use "src/lexer" lx
use "src/open_file" opf

use "src/pipeline" pipe

pub main(args str[]) !void:
    # TODO: handle args
    filePath str
    unsafe filePath = args[1]

    stdout := try io.stdout()
    defer stdout.close()

    gl.logger = log.new(stdout.writer(), log.LVL_DEFAULT)
    gl.logger.logLn("Starting...")

    # initialize required pipeline data
    try gl.initGlobal()
    try tkt.initKwMap()

    gl.cwd = try fs.currentDir()
    gl.logger.log("CWD: ")
    gl.logger.logLn(gl.cwd)

    absolute := try mk_abs.makeAbsolute(filePath, "")
    defer absolute.free()

    gl.logger.log("PATH: ")
    gl.logger.logLn(absolute)

    fileCtx := try opf.openFile(absolute)
    f := addrof fileCtx

    gl.logger.log("MODNAME: ")
    gl.logger.logLn(f.modName)

    gl.logger.log("CONTENT: ")
    gl.logger.logLn(f.content)

    future := try pipe.pipelineAsync(f)
    pipeErr := try future.await()

    # TODO: infer num literals as enum
    #test comperr.Severity = 0

    e := comperr.CompErr(
        code="TEST"
        file=f,
        org=org.Origin(filePath=f.path, position=org.FilePos(line=0, column=5)),
        sev=cast.u64to8(0),
        msg="This is a test.",
        help="nothing to see here."
    )
    e.log()

    ret
..
