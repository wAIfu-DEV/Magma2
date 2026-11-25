mod compiler_timings

use "std:sort" sort
use "std:list" ls
use "std:time" time
use "helper/logger" log
use "shared/global" gl
use "shared/filectx" fctx

sort(a u64, b u64) i64:
    if a < b: ret -1 ..
    if a > b: ret 1 ..
    ret 0
..

pub printTimings(pipelineElapsedMs u64, checkElapsedMs u64, cacheLookupElapsedMs u64, loweringElapsedMs u64, assemblyWaitElapsedMs u64, linkElapsedMs u64, backendElapsedMs u64, unmeasuredMs u64, elapsedTotalMs u64) !void:
    try gl.startLog(log.LogLevel.DEFAULT).writeLn("Compilation timings:").end()
    gl.lockTimings.lock()
    lexTimes := gl.timingLex.view()
    parseTimes := gl.timingParse.view()
    timingCount := gl.timingLex.count()
    lexAverage u64 = 0
    parseAverage u64 = 0
    lexP99 u64 = 0
    parseP99 u64 = 0
    if timingCount > 0:
        sort.quick[u64](lexTimes, sort)
        sort.quick[u64](parseTimes, sort)
        lexTotal u64 = 0
        parseTotal u64 = 0
        for i := 0 to timingCount:
            lexTotal = lexTotal + lexTimes[i]
            bounded i < parseTimes.count():
                parseTotal = parseTotal + parseTimes[i]
            ..
        ..
        p99Index := (timingCount * 99 + 99) / 100 - 1
        lexAverage = lexTotal / timingCount
        parseAverage = parseTotal / timingCount
        bounded p99Index < lexTimes.count():
            lexP99 = lexTimes[p99Index]
        ..
        bounded p99Index < parseTimes.count():
            parseP99 = parseTimes[p99Index]
        ..
    ..
    gl.lockTimings.unlock()

    try gl.startLog(log.LogLevel.DEFAULT).write("  Async pipeline:   ").writeUint64(pipelineElapsedMs).writeLn("ms").end()
    if timingCount > 0:
        try gl.startLog(log.LogLevel.DEFAULT).write("    Lexing:         avg: ").writeUint64(lexAverage).write("µs, p99: ").writeUint64(lexP99).writeLn("µs").end()
        try gl.startLog(log.LogLevel.DEFAULT).write("    Parsing:        avg: ").writeUint64(parseAverage).write("µs, p99: ").writeUint64(parseP99).writeLn("µs").end()
    ..
    try gl.startLog(log.LogLevel.DEFAULT).write("\n  Semantic check:   ").writeUint64(checkElapsedMs).writeLn("ms").end()
    try gl.startLog(log.LogLevel.DEFAULT).write("  LLVM backend:     ").writeUint64(backendElapsedMs).writeLn("ms").end()
    try gl.startLog(log.LogLevel.DEFAULT).write("    Cache lookup:   ").writeUint64(cacheLookupElapsedMs).writeLn("ms").end()
    try gl.startLog(log.LogLevel.DEFAULT).write("    IR lowering:    ").writeUint64(loweringElapsedMs).writeLn("ms").end()
    try gl.startLog(log.LogLevel.DEFAULT).write("    Assembly wait:  ").writeUint64(assemblyWaitElapsedMs).writeLn("ms (overlaps lowering)").end()
    try gl.startLog(log.LogLevel.DEFAULT).write("    ThinLTO link:   ").writeUint64(linkElapsedMs).writeLn("ms").end()
    try gl.startLog(log.LogLevel.DEFAULT).write("  Other:            ").writeUint64(unmeasuredMs).writeLn("ms").end()
    try gl.startLog(log.LogLevel.DEFAULT).write("  Total:            ").writeUint64(elapsedTotalMs).writeLn("ms").end()
    try gl.startLog(log.LogLevel.DEFAULT).write("\n  File count:       ").writeUint64(timingCount).writeLn("\n").end()
..

printFileTiming(file fctx.FileCtx*, pathWidth u64, lexWidth u64, parseWidth u64, checkWidth u64) !void:
    w := try gl.startLog(log.LogLevel.DEFAULT)
    defer w.end()
    try w.write("  ").write(file.path)
    for i := file.path.countBytes() to pathWidth:
        try w.write(" ")
    ..
    try w.write("  ")
    for i := digits(file.lexingUs) to lexWidth:
        try w.write(" ")
    ..
    try w.writeUint64(file.lexingUs).write("µs")
    try w.write("  ")
    for i := digits(file.parsingUs) to parseWidth:
        try w.write(" ")
    ..
    try w.writeUint64(file.parsingUs).write("µs")
    try w.write("  ")
    for i := digits(file.checkingUs) to checkWidth:
        try w.write(" ")
    ..
    try w.writeUint64(file.checkingUs).writeLn("µs")
..

digits(value u64) u64:
    count u64 = 1
    remaining := value
    loop remaining >= 10:
        remaining = remaining / 10
        count = count + 1
    ..
    ret count
..

pub printTimingsPerFile(root fctx.FileCtx*) !void:
    try gl.startLog(log.LogLevel.DEFAULT).writeLn("Per-file timings:").end()
    files := try ls.new[fctx.FileCtx*](ctx.alloc, none)
    defer files.free()
    try files.pushRight(root)
    for i := 0 to gl.importedFiles.count():
        file := try gl.importedFiles.get(i)
        try files.pushRight(file)
    ..
    sort.quick[fctx.FileCtx*](files.view(), compareFileTiming)

    pathWidth := root.path.countBytes()
    lexWidth := digits(root.lexingUs)
    parseWidth := digits(root.parsingUs)
    checkWidth := digits(root.checkingUs)
    for i := 0 to gl.importedFiles.count():
        file := try gl.importedFiles.get(i)
        if file.path.countBytes() > pathWidth:
            pathWidth = file.path.countBytes()
        ..
        if digits(file.lexingUs) > lexWidth:
            lexWidth = digits(file.lexingUs)
        ..
        if digits(file.parsingUs) > parseWidth:
            parseWidth = digits(file.parsingUs)
        ..
        if digits(file.checkingUs) > checkWidth:
            checkWidth = digits(file.checkingUs)
        ..
    ..
    w := try gl.startLog(log.LogLevel.DEFAULT)
    defer w.end()
    try w.write("  ")
    for i := 0 to pathWidth:
        try w.write(" ")
    ..
    try w.write("  ")
    try w.write("Lex")
    for i := 0 to lexWidth + 2 - 3:
        try w.write(" ")
    ..
    try w.write("  ")
    try w.write("Parse")
    for i := 0 to parseWidth + 2 - 5:
        try w.write(" ")
    ..
    try w.write("  ")
    try w.write("Check")
    for i := 0 to checkWidth + 2 - 5:
        try w.write(" ")
    ..
    try w.writeLn("")
    for i := 0 to files.count():
        file := try files.get(i)
        try printFileTiming(file, pathWidth, lexWidth, parseWidth, checkWidth)
    ..
..

compareFileTiming(a fctx.FileCtx*, b fctx.FileCtx*) i64:
    aTotal := a.lexingUs + a.parsingUs + a.checkingUs
    bTotal := b.lexingUs + b.parsingUs + b.checkingUs
    if aTotal > bTotal:
        ret -1
    ..
    if aTotal < bTotal:
        ret 1
    ..
    ret 0
..
