mod pipeline

use "std:future" future
use "std:abort" abort
use "std:errors" errs
use "std:strings" strgs
use "std:time" time
use "std:io" io

use "shared/filectx" fctx
use "lexer" lx
use "shared/global" gl
use "shared/token_types" tkt
use "open_file" opf
use "node_printer" node_printer
use "parser" parser
use "helper/logger" log

# thin wrapper around file context, prevents copy
fw(
    f fctx.FileCtx*,
)

pathWork(
    path str,
)

pipelineEntry(w fw*, a abort.Signal) !error:
    gl.runningPipelines.fetchAdd(1)
    defer gl.runningPipelines.fetchSub(1)

    start := time.ticks()

    f := w.f

    try gl.startLog(log.LogLevel.DEBUG).write("STARTED ").writeLn(f.path).end()

    f.tokens = try lx.run(f)

    lexElapasedUs := time.elapsedUs(start)
    start = time.ticks()

    if gl.logger.level <= log.LogLevel.VERBOSE:
        try lx.printTokens(f)
    ..

    try parser.run(f)

    if gl.logger.level <= log.LogLevel.VERBOSE:
        try node_printer.printRoot(addrof f.astRoot)
    ..

    parseElapasedUs := time.elapsedUs(start)

    w2 := try gl.startLog(log.LogLevel.DEBUG)
    try w2.write("ENDED ").writeLn(f.path)
    try w2.write("  LEX ").writeUint64(lexElapasedUs)
    try w2.write("µs PARSE ").writeUint64(parseElapasedUs).writeLn("µs")
    w2.end()

    ret errs.ok()
..

pub pipelineAsync(f fctx.FileCtx*) !$future.Future[error]:
    ret try future.newAbort[error, fw](ctx.exec, pipelineEntry, fw(f=f))
..

pipelinePathEntry(w pathWork*, a abort.Signal) !error:
    file := try opf.openFile(w.path)
    filePtr := try retainImportedFile(move file)

    stored := fw(f=filePtr)
    ret try pipelineEntry(addrof stored, a)
..

retainImportedFile(file $fctx.FileCtx) !fctx.FileCtx*:
    f fctx.FileCtx* = none
    if true:
        gl.lockImportedFiles.lock()
        defer gl.lockImportedFiles.unlock()
        id := gl.importedFiles.count()
        try gl.importedFiles.push(move file)
        f = try gl.importedFiles.get(id)
    ..
    if true:
        gl.lockFiles.lock()
        defer gl.lockFiles.unlock()
        try gl.files.setBorrowed(f.path, f)
    ..
    ret f
..

pub pipelinePathAsync(path str) !$future.Future[error]:
    ownedPath := try strgs.copy(path)
    ret try future.newAbort[error, pathWork](ctx.exec, pipelinePathEntry, pathWork(path=move ownedPath))
..

pub pipelineSync(f fctx.FileCtx*) !error:
    abctrl := try abort.new()
    defer abctrl.close()
    w := fw(f=f)
    ret try pipelineEntry(addrof w, abctrl.signal())
..

pub setupRunner() void:
    gl.pipelineRunner = pipelinePathAsync
..
