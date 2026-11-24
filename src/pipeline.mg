mod pipeline

use "std:future" future
use "std:abort" abort
use "std:errors" errs
use "std:strings" strgs
use "std:time" time
use "std:io" io
use "std:list" ls

use "shared/filectx" fctx
use "lexer" lx
use "shared/global" gl
use "shared/token_types" tkt
use "open_file" opf
use "node_printer" node_printer
use "parser" parser
use "link_checker" link_checker
use "safety_checker" safety_checker
use "helper/logger" log

# thin wrapper around file context, prevents copy
fw(
    f fctx.FileCtx*,
)

pathWork(
    path str,
)

pipelineEntry(w fw*, a abort.Signal) !error:
    defer gl.runningPipelines.fetchSub(1)

    start := time.ticks()

    f := w.f

    try gl.startLog(log.LogLevel.DEBUG).write("STARTED ").writeLn(f.path).end()

    f.tokens = try lx.run(f)

    lexElapasedUs := time.elapsedUs(start)
    f.lexingUs = lexElapasedUs
    start = time.ticks()

    if gl.logger.level <= log.LogLevel.VERBOSE:
        try lx.printTokens(f)
    ..

    try parser.run(f)

    if gl.logger.level <= log.LogLevel.VERBOSE:
        try node_printer.printRoot(addrof f.astRoot)
    ..

    parseElapasedUs := time.elapsedUs(start)
    f.parsingUs = parseElapasedUs

    gl.lockTimings.lock()
    defer gl.lockTimings.unlock()
    try gl.timingLex.pushRight(lexElapasedUs)
    try gl.timingParse.pushRight(parseElapasedUs)

    w2 := try gl.startLog(log.LogLevel.DEBUG)
    defer w2.end()
    try w2.write("ENDED ").writeLn(f.path)
    try w2.write("  LEX ").writeUint64(lexElapasedUs)
    try w2.write("µs PARSE ").writeUint64(parseElapasedUs).writeLn("µs")
    ret errs.ok()
..

pub pipelineAsync(f fctx.FileCtx*) !$future.Future[error]:
    gl.runningPipelines.fetchAdd(1)

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
    gl.runningPipelines.fetchAdd(1)
    onerror gl.runningPipelines.fetchSub(1)

    ownedPath := try strgs.copy(path)
    ret try future.newAbort[error, pathWork](ctx.exec, pipelinePathEntry, pathWork(path=move ownedPath))
..

pub pipelineSync(f fctx.FileCtx*) !error:
    gl.runningPipelines.fetchAdd(1)
    onerror gl.runningPipelines.fetchSub(1)

    abctrl := try abort.new()
    defer abctrl.close()
    w := fw(f=f)
    ret try pipelineEntry(addrof w, abctrl.signal())
..

checkParsedGraph(file fctx.FileCtx*, rootPath str, visited ls.List[str]*, files fctx.FileArray*, waitForParse bool) !void:
    for i := 0 to visited.count():
        prior := try visited.get(i)
        if strgs.compare(prior, file.path):
            ret
        ..
    ..

    if waitForParse && not strgs.compare(file.path, rootPath):
        pipeline := try gl.pipelines.take(file.path)
        pipelineResult, awaitErr := pipeline.await()
        if awaitErr.nok():
            try gl.startLog(log.LogLevel.DEFAULT).write("PARSE THREW ").writeLn(file.path).end()
            throw awaitErr
        ..
        if pipelineResult.code() != 0:
            try gl.startLog(log.LogLevel.DEFAULT).write("PARSE FAILED ").writeLn(file.path).end()
            throw pipelineResult
        ..
    ..

    try visited.pushRight(strgs.copy(file.path))

    for i := 0 to file.imports.count():
        importPath := try file.imports.get(i)
        alreadyVisited := false
        for j := 0 to visited.count():
            prior := try visited.get(j)
            if strgs.compare(prior, importPath):
                alreadyVisited = true
                break
            ..
        ..
        if alreadyVisited:
            continue
        ..
        importedFile := try gl.files.get(importPath)
        try checkParsedGraph(importedFile, rootPath, visited, files, waitForParse)
    ..
    try files.pushRight(ctx.alloc, file)
..

pub checkGraph(root fctx.FileCtx*) !error:
    visited := try ls.new[str](ctx.alloc, none)
    defer visited.free()
    files := fctx.emptyFileArray()
    try checkParsedGraph(root, root.path, addrof visited, addrof files, true)
    try link_checker.runGraph(files)
    ret try safety_checker.runGraph(files)
..

# Reconstruct the dependency-first graph after checking for backend consumers.
# FileCtx objects are retained by the frontend for the duration of the build.
pub collectCheckedGraph(root fctx.FileCtx*) !$fctx.FileArray:
    visited := try ls.new[str](ctx.alloc, none)
    defer visited.free()
    files := fctx.emptyFileArray()
    try checkParsedGraph(root, root.path, addrof visited, addrof files, false)
    ret files
..

pub setupRunner() void:
    gl.pipelineRunner = pipelinePathAsync
..
