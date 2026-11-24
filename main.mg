mod main

use "std:io" io
use "std:fs" fs
use "std:cast" cast
use "std:path" path
use "std:time" time
use "std:thread" thread
use "std:thread_pool" thread_pool
use "std:cpu" cpu
use "std:context" context
use "std:heap" heap
use "std:flag" flag
use "std:errors" errors
use "std:process" proc
use "std:strings" strings
use "std:sort" sort
use "std:list" ls
use "std:stable_list" stable
use "std:future" fut

use "src/helper/logger" log
use "src/shared/token_types" tkt
use "src/shared/comperr" comperr
use "src/shared/origin" org
use "src/make_absolute" mk_abs
use "src/compiler_version" compiler_version
use "src/llvm_cache" llvm_cache
use "src/llvm_cache_fingerprint" llvm_cache_fingerprint
use "src/llvm_lowering" llvm_lowering

BackendWork(
    file fctx.FileCtx*
    loweringInputs str
    llvmText str
)

# Edit these constants to compare the serial and parallel backend stages.
# Parallel fingerprinting memoizes each module's interface under a read/write lock.
const PARALLEL_CACHE_LOOKUP bool = true
const PARALLEL_MODULE_LOWERING bool = true

CacheLookupWork(
    cache llvm_cache.Cache*
    file fctx.FileCtx*
    fingerprint str*
    result llvm_cache.Lookup*
)

InterfaceFingerprintWork(
    file fctx.FileCtx*
    result str*
)

LoweringFingerprintWork(
    file fctx.FileCtx*
    cache llvm_cache_fingerprint.FingerprintCache*
    result str*
)

LoweringWork(
    work BackendWork*
)

runCacheLookup(work CacheLookupWork*) !error:
    unsafe:
        work.result.close()
        *work.result = try llvm_cache.lookupRecover(work.cache, work.file, *work.fingerprint)
    ..
    ret errors.ok()
..

runInterfaceFingerprint(work InterfaceFingerprintWork*) !error:
    unsafe: *work.result = try llvm_cache_fingerprint.fingerprint(work.file) ..
    ret errors.ok()
..

runLoweringFingerprint(work LoweringFingerprintWork*) !error:
    unsafe: *work.result = try llvm_cache_fingerprint.loweringInputsFingerprint(work.file, work.cache) ..
    ret errors.ok()
..

runLowering(work LoweringWork*) !error:
    unsafe: work.work.llvmText = try llvm_lowering.emitModule(work.work.file) ..
    ret errors.ok()
..

cleanupFingerprint(value $str) void:
    value.free()
..

emptyLookup() !$llvm_cache.Lookup:
    ret llvm_cache.Lookup(hit=false, bitcode=try strings.alloc(0), reason="")
..

cleanupLookup(value $llvm_cache.Lookup) void:
    value.close()
..

use "src/shared/global" gl
use "src/shared/filectx" fctx
use "src/lexer" lx
use "src/open_file" opf
use "src/parser" parser
use "src/node_printer" node_printer
use "src/pipeline" pipe

cleanupAssemblyFuture(value $fut.Future[error]) void:
    # Futures can still be publishing cache entries when later module lowering
    # fails. StableList cleanup runs before the cache and pending work defers.
    result, awaitError := value.await()
    result = result
    awaitError = awaitError
..

ToolVersions(
    llvmVersionText str
    optVersionText str
    clangVersionText str
)

destr ToolVersions.free() void:
    this.llvmVersionText.free()
    this.optVersionText.free()
    this.clangVersionText.free()
..

runToolVersionProbe(task bool*) !$str:
    task = task
    llvmOutput := try proc.capture("llvm-as", []str("--version"))
    defer llvmOutput.free()
    optOutput := try proc.capture("opt", []str("--version"))
    defer optOutput.free()
    clangOutput := try proc.capture("clang", []str("--version"))
    defer clangOutput.free()
    separator := "\n--MAGMA-TOOL-VERSION--\n"
    llvmAndSeparator := try strings.concat(llvmOutput, separator)
    defer llvmAndSeparator.free()
    llvmOpt := try strings.concat(llvmAndSeparator, optOutput)
    defer llvmOpt.free()
    llvmOptSeparator := try strings.concat(llvmOpt, separator)
    defer llvmOptSeparator.free()
    ret try strings.concat(llvmOptSeparator, clangOutput)
..

startToolVersionProbe() !$fut.Future[str]:
    ret try fut.new[str, bool](ctx.exec, runToolVersionProbe, true)
..

awaitToolVersion(value $fut.Future[str]) !$str:
    ret try value.await()
..

awaitAndFreeToolVersion(value $fut.Future[str]) !bool:
    output := try awaitToolVersion(move value)
    output.free()
    ret true
..

discardToolVersionFuture(value $fut.Future[str]) void:
    drained bool, awaitError error = awaitAndFreeToolVersion(move value)
    drained = drained
    awaitError = awaitError
..

decodeToolVersions(encoded str) !$ToolVersions:
    parts := try strings.split(encoded, "\n--MAGMA-TOOL-VERSION--\n")
    defer parts.free()
    if parts.size != 3: throw errors.invalidArgument("invalid tool version result") ..
    llvmVersionText := try strings.copy(parts.get(0))
    onerror llvmVersionText.free()
    optVersionText := try strings.copy(parts.get(1))
    onerror optVersionText.free()
    clangVersionText := try strings.copy(parts.get(2))
    ret ToolVersions(
        llvmVersionText=move llvmVersionText,
        optVersionText=move optVersionText,
        clangVersionText=move clangVersionText,
    )
..

discardErrorFuture(value $fut.Future[error]) void:
    output error, awaitError error = value.await()
    output = output
    awaitError = awaitError
..

registerRootPipeline(path str, future fut.Future[error]) !bool:
    try gl.pipelines.setBorrowed(path, future)
    ret true
..

cleanupLookupFuture(value $fut.Future[error]) void:
    result, awaitError := value.await()
    result = result
    awaitError = awaitError
..

cleanupLoweringFuture(value $fut.Future[error]) void:
    result, awaitError := value.await()
    result = result
    awaitError = awaitError
..

pub main(args str[]) !u32:
    startTicks := time.ticks()

    allocator := heap.allocator()

    # ----------- #
    # ARG PARSING #
    # ----------- #

    flags := try flag.new(allocator, "magma")
    defer flags.free()

    flagThreads u64
    flags.unsigned("threads", 't', addrof flagThreads, "maximum allowed concurrent threads for compilation, default -t0 (cpu core count)")

    flagOpt u64 = 3
    flags.unsigned("opt", 'O', addrof flagOpt, "optimization level used by LLVM, default is -O3")

    flagTimings bool
    flags.boolean("timings", 'T', addrof flagTimings, "prints timings for each steps of the compilation")

    flagTimingsPerFile bool
    flags.boolean("timings-per-file", 0, addrof flagTimingsPerFile, "prints lex, parse and check timings for each file")

    flagDebug bool
    flags.boolean("debug", 'd', addrof flagDebug, "prints additional debug logs")

    flagVerbose bool
    flags.boolean("verbose", 'V', addrof flagVerbose, "prints more logs than --debug")

    flagExplainCache bool
    flags.boolean("explain-cache", 0, addrof flagExplainCache, "prints the cache decision and miss reason for each module")

    flagVersion bool # TODO: implement
    flags.boolean("version", 'v', addrof flagVersion, "prints the compiler's version, does not proceed with compilation")

    flagRun bool # TODO: implement
    flags.boolean("run", 'r', addrof flagRun, "runs the executable after compilation")

    flagOut str # TODO: implement
    flags.string("output", 'o', addrof flagOut, "path to the output the compiler will write to")

    flagIn str # TODO: implement
    flags.string("input", 'i', addrof flagIn, "path to the input magma file, alternative to positional arg")

    flagEmit str # TODO: implement
    flags.string("emit", 'e', addrof flagEmit, "what type of output the compiler should write ('exe','llvm') default is 'exe'")

    flagHelp bool
    flags.boolean("help", 'h', addrof flagHelp, "prints the available args for magma")

    flagRes := try flags.parse(args)
    defer flagRes.free()

    # ------------ #
    # CONTEXT INIT #
    # ------------ #

    cores := cpu.coreCount()
    if flagThreads != 0:
        cores = flagThreads
    ..
    minCores u64 = 1

    tp := try thread_pool.new(allocator, minCores, cores, 512, minCores) # TODO: 512 might be an issue, have to check
    defer tp.close()
    ctx = context.new(allocator, tp.executor())

    gl.stdin = try io.stdin()
    gl.stdout = try io.stdout()

    if flagVersion:
        try io.printLn(compiler_version.VERSION)
        ret 0
    ..

    # ------------- #
    # FLAG HANDLING #
    # ------------- #

    if flagHelp || args.count() == 1:
        try flags.writeUsage(gl.stdout.writer())
        ret 0
    ..

    logLevel := log.LogLevel.DEFAULT
    if flagVerbose:
        logLevel = log.LogLevel.VERBOSE
    elif flagDebug:
        logLevel = log.LogLevel.DEBUG
    ..

    gl.logger = log.new(gl.stdout.writer(), logLevel)

    posArgs := flagRes.positionals()
    posArgsCnt := posArgs.count()

    filePath str
    if posArgsCnt <= 1 && flagIn == "":
        throw errors.invalidArgument("missing positional argument or --input flag for the input magma file")
    elif posArgsCnt > 2:
        throw errors.invalidArgument("cannot have more than 1 positional argument")
    elif flagIn != "":
        filePath = flagIn
    else: # count == 2
        unsafe filePath = posArgs[1]
    ..

    # --------- #
    # DATA INIT #
    # --------- #

    # initialize required pipeline data
    try gl.initGlobal()
    try tkt.initKwMap()
    pipe.setupRunner()  # used to prevent circular deps in pipeline
                        # since parser calls
                        # TODO: delete the concept of circular deps

    try gl.startLog(log.LogLevel.DEBUG).writeLn("after data init").end()

    # ---------- #
    # INPUT FILE #
    # ---------- #

    gl.cwd = try fs.currentDir()
    gl.stdLibRoot = try path.join([]str(gl.cwd, "std"))

    # startLog returns a writer and locks the stdout for other threads until .end is called
    # this keeps printed lines uninterrupted by concurrent writes
    try gl.startLog(log.LogLevel.DEBUG).write("CWD ").writeLn(gl.cwd).end()

    absolute := try mk_abs.makeAbsolute(filePath, "")
    defer absolute.free()

    try gl.startLog(log.LogLevel.DEBUG).write("PATH ").writeLn(absolute).end()

    fileCtx := try opf.openFile(absolute)
    f := addrof fileCtx

    gl.lockFiles.lock()
    onerror gl.lockFiles.unlock()
    try gl.files.setBorrowed(absolute, f)
    gl.lockFiles.unlock()

    try gl.startLog(log.LogLevel.DEBUG).write("SETUP ").writeUint64(time.elapsedUs(startTicks)).writeLn("µs").end()

    try gl.startLog(log.LogLevel.DEBUG).writeLn("after input file handling").end()

    # ---------------------- #
    # MULTITHREADED PIPELINE #
    # ---------------------- #

    pipelineStartTick := time.ticks()

    # future is akin to JS's Promise but uses the context's executor, here the thread pool
    future := try pipe.pipelineAsync(f)
    toolVersionFuture fut.Future[str], toolLaunchError error = startToolVersionProbe()
    if toolLaunchError.nok():
        discardErrorFuture(move future)
        throw toolLaunchError
    ..

    gl.lockPipelines.lock()
    registered bool, registerError error = registerRootPipeline(absolute, future)
    gl.lockPipelines.unlock()
    if registerError.nok():
        discardErrorFuture(move future)
        discardToolVersionFuture(move toolVersionFuture)
        throw registerError
    ..

    pipeErr error, pipeFutureError error = future.await()

    # once main pipe is done, it waits for other pipes to finish
    loop gl.runningPipelines.load() > 0:
        thread.yield() # yields to OS scheduler
    ..

    toolVersionOutput := try awaitToolVersion(move toolVersionFuture)
    defer toolVersionOutput.free()

    if pipeFutureError.nok(): throw pipeFutureError ..
    if pipeErr.nok(): throw pipeErr ..

    toolVersions := try decodeToolVersions(toolVersionOutput)
    defer toolVersions.free()

    pipelineElapsedMs := time.elapsedMs(pipelineStartTick)

    try gl.startLog(log.LogLevel.DEBUG).writeLn("after multithreaded pipeline").end()

    # ----------------------------- #
    # SYNC SEMANTIC AND TYPE CHECKS #
    # ----------------------------- #

    checkStart := time.ticks()
    semanticErr := try pipe.checkGraph(f)
    checkElapsedMs := time.elapsedMs(checkStart)
    if semanticErr.nok():
        throw semanticErr
    ..

    try gl.startLog(log.LogLevel.DEBUG).writeLn("after semcheck").end()

    backendStartTick := time.ticks()
    cacheLookupStartTick := time.ticks()

    # Cache validation belongs after the complete checked graph and before any
    # module lowering.
    llvmAsVersion := try strings.concat("llvm-as:\n", toolVersions.llvmVersionText)
    defer llvmAsVersion.free()
    optToolVersion := try strings.concat("opt:\n", toolVersions.optVersionText)
    defer optToolVersion.free()
    clangToolVersion := try strings.concat("clang:\n", toolVersions.clangVersionText)
    defer clangToolVersion.free()
    toolsVersion := try strings.concat(llvmAsVersion, optToolVersion)
    defer toolsVersion.free()
    allToolsVersion := try strings.concat(toolsVersion, clangToolVersion)
    defer allToolsVersion.free()
    versionPrefix := try strings.concat(compiler_version.VERSION, "\n")
    defer versionPrefix.free()
    cacheVersion := try strings.concat(versionPrefix, allToolsVersion)
    defer cacheVersion.free()
    cache := try llvm_cache.open(gl.cwd, cacheVersion, compiler_version.TARGET_TRIPLE)
    defer cache.close()

    if flagExplainCache:
        cacheLocation := try path.join([]str(gl.cwd, ".magma"))
        defer cacheLocation.free()
        try gl.startLog(log.LogLevel.DEFAULT).write("LLVM cache: ").writeLn(cacheLocation).end()
        if cache.discardedIncompatible:
            try gl.startLog(log.LogLevel.DEFAULT).writeLn("LLVM cache namespace discarded: compiler or LLVM version changed")
        ..
    ..

    # Resolve all module cache entries only after the complete graph has been
    # checked. The backend receives dependencies first, matching link order.
    checkedFiles := try pipe.collectCheckedGraph(f)
    pendingModules := try stable.new[BackendWork](ctx.alloc, none)
    defer pendingModules.free()
    fingerprintCache := try llvm_cache_fingerprint.newFingerprintCache()
    defer fingerprintCache.close()
    interfaceFingerprints := try stable.new[str](ctx.alloc, cleanupFingerprint)
    defer interfaceFingerprints.free()
    loweringFingerprints := try stable.new[str](ctx.alloc, cleanupFingerprint)
    defer loweringFingerprints.free()
    lookupFutures := try stable.new[fut.Future[error]](ctx.alloc, cleanupLookupFuture)
    defer lookupFutures.free()
    lookupResults := try stable.new[llvm_cache.Lookup](ctx.alloc, cleanupLookup)
    defer lookupResults.free()
    for i := 0 to checkedFiles.count():
        emptyResult := try emptyLookup()
        try lookupResults.push(move emptyResult)
        emptyInterface := try strings.alloc(0)
        try interfaceFingerprints.push(move emptyInterface)
        emptyLowering := try strings.alloc(0)
        try loweringFingerprints.push(move emptyLowering)
    ..
    if PARALLEL_CACHE_LOOKUP:
        interfaceFutures := try stable.new[fut.Future[error]](ctx.alloc, cleanupAssemblyFuture)
        defer interfaceFutures.free()
        for i := 0 to checkedFiles.count():
            try interfaceFutures.push(fut.Future[error](state=none))
        ..
        for i := 0 to checkedFiles.count():
            moduleFile := try checkedFiles.get(i)
            resultSlot := try interfaceFingerprints.get(i)
            futureSlot := try interfaceFutures.get(i)
            pending := try fut.new[error, InterfaceFingerprintWork](ctx.exec, runInterfaceFingerprint, InterfaceFingerprintWork(file=moduleFile, result=resultSlot))
            unsafe: *futureSlot = move pending ..
        ..
        for i := 0 to checkedFiles.count():
            fingerprintResult, fingerprintError := (try interfaceFutures.get(i)).await()
            if fingerprintError.nok(): throw fingerprintError ..
            if fingerprintResult.nok(): throw fingerprintResult ..
            moduleFile := try checkedFiles.get(i)
            fingerprint := try interfaceFingerprints.get(i)
            unsafe: try fingerprintCache.store(moduleFile.path, *fingerprint) ..
        ..
        loweringFutures := try stable.new[fut.Future[error]](ctx.alloc, cleanupAssemblyFuture)
        defer loweringFutures.free()
        for i := 0 to checkedFiles.count():
            try loweringFutures.push(fut.Future[error](state=none))
        ..
        for i := 0 to checkedFiles.count():
            moduleFile := try checkedFiles.get(i)
            resultSlot := try loweringFingerprints.get(i)
            futureSlot := try loweringFutures.get(i)
            pending := try fut.new[error, LoweringFingerprintWork](ctx.exec, runLoweringFingerprint, LoweringFingerprintWork(file=moduleFile, cache=addrof fingerprintCache, result=resultSlot))
            unsafe: *futureSlot = move pending ..
        ..
        for i := 0 to checkedFiles.count():
            fingerprintResult, fingerprintError := (try loweringFutures.get(i)).await()
            if fingerprintError.nok(): throw fingerprintError ..
            if fingerprintResult.nok(): throw fingerprintResult ..
        ..
        for i := 0 to checkedFiles.count():
            try lookupFutures.push(fut.Future[error](state=none))
        ..
        for i := 0 to checkedFiles.count():
            moduleFile := try checkedFiles.get(i)
            resultSlot := try lookupResults.get(i)
            fingerprint := try loweringFingerprints.get(i)
            work := CacheLookupWork(cache=addrof cache, file=moduleFile, fingerprint=fingerprint, result=resultSlot)
            futureSlot := try lookupFutures.get(i)
            pending := try fut.new[error, CacheLookupWork](ctx.exec, runCacheLookup, work)
            unsafe: *futureSlot = move pending ..
        ..
    else:
        for i := 0 to checkedFiles.count():
            moduleFile := try checkedFiles.get(i)
            fingerprint := try llvm_cache_fingerprint.fingerprint(moduleFile)
            onerror fingerprint.free()
            try fingerprintCache.store(moduleFile.path, fingerprint)
            fingerprint.free()
        ..
        for i := 0 to checkedFiles.count():
            moduleFile := try checkedFiles.get(i)
            resultSlot := try loweringFingerprints.get(i)
            fingerprint := try llvm_cache_fingerprint.loweringInputsFingerprint(moduleFile, addrof fingerprintCache)
            unsafe: *resultSlot = move fingerprint ..
        ..
    ..
    for i := 0 to checkedFiles.count():
        moduleFile := try checkedFiles.get(i)
        cached := try lookupResults.get(i)
        if PARALLEL_CACHE_LOOKUP:
            cacheResult, awaitError := (try lookupFutures.get(i)).await()
            if awaitError.nok(): throw awaitError ..
            if cacheResult.nok(): throw cacheResult ..
        else:
            fingerprint := try loweringFingerprints.get(i)
            unsafe:
                *cached = try llvm_cache.lookupRecover(addrof cache, moduleFile, *fingerprint)
            ..
        ..
        if cached.hit:
            if flagExplainCache:
                try gl.startLog(log.LogLevel.DEFAULT).write("LLVM cache hit: ").writeLn(moduleFile.path).end()
            else:
                try gl.startLog(log.LogLevel.DEBUG).write("LLVM CACHE HIT ").writeLn(moduleFile.path).end()
            ..
        else:
            if flagExplainCache:
                try gl.startLog(log.LogLevel.DEFAULT).write("LLVM cache miss: ").write(moduleFile.path).write(" (").write(cached.reason).writeLn(")").end()
            else:
                try gl.startLog(log.LogLevel.DEBUG).write("LLVM CACHE MISS ").write(moduleFile.path).write(" (").write(cached.reason).writeLn(")").end()
            ..
            fingerprint := try loweringFingerprints.get(i)
            unsafe:
                try pendingModules.push(BackendWork(file=moduleFile, loweringInputs=try strings.copy(*fingerprint), llvmText=""))
            ..
        ..
    ..

    try gl.startLog(log.LogLevel.DEBUG).writeLn("after resolve cache").end()
    cacheLookupElapsedMs := time.elapsedMs(cacheLookupStartTick)

    # Start assembling each miss as soon as its text is ready. The next module
    # is lowered while llvm-as runs on the shared executor.
    assemblyFutures := try stable.new[fut.Future[error]](ctx.alloc, cleanupAssemblyFuture)
    defer assemblyFutures.free()
    loweringElapsedMs u64 = 0
    # Allocate every future slot before starting workers. If growing the list
    # failed after submission, the new worker would have no handle for unwind
    # cleanup to await.
    for i := 0 to pendingModules.count():
        try assemblyFutures.push(fut.Future[error](state=none))
    ..
    if PARALLEL_MODULE_LOWERING:
        lowerFutures := try stable.new[fut.Future[error]](ctx.alloc, cleanupLoweringFuture)
        defer lowerFutures.free()
        for i := 0 to pendingModules.count():
            try lowerFutures.push(fut.Future[error](state=none))
        ..
        loweringStartTick := time.ticks()
        for i := 0 to pendingModules.count():
            work := try pendingModules.get(i)
            if flagDebug || flagVerbose:
                try gl.startLog(log.LogLevel.DEBUG).write("LLVM LOWER ").writeLn(work.file.path).end()
            ..
            lowerFuture := try fut.new[error, LoweringWork](ctx.exec, runLowering, LoweringWork(work=work))
            onerror cleanupLoweringFuture(move lowerFuture)
            futureSlot := try lowerFutures.get(i)
            unsafe: *futureSlot = move lowerFuture ..
        ..
        for i := 0 to pendingModules.count():
            assemblySlot := try assemblyFutures.get(i)
            work := try pendingModules.get(i)
            lowerFuture := try lowerFutures.get(i)
            lowerResult, lowerError := lowerFuture.await()
            if lowerError.nok(): throw lowerError ..
            if lowerResult.nok(): throw lowerResult ..
            assembly := try llvm_cache.assembleAsync(addrof cache, work.file, work.loweringInputs, work.llvmText, flagOpt)
            unsafe: *assemblySlot = move assembly ..
        ..
        loweringElapsedMs = time.elapsedMs(loweringStartTick)
    else:
        for i := 0 to pendingModules.count():
            assemblySlot := try assemblyFutures.get(i)
            work := try pendingModules.get(i)
            if flagDebug || flagVerbose:
                try gl.startLog(log.LogLevel.DEBUG).write("LLVM LOWER ").writeLn(work.file.path).end()
            ..
            loweringStartTick := time.ticks()
            work.llvmText = try llvm_lowering.emitModule(work.file)
            loweringElapsedMs = loweringElapsedMs + time.elapsedMs(loweringStartTick)
            assembly := try llvm_cache.assembleAsync(addrof cache, work.file, work.loweringInputs, work.llvmText, flagOpt)
            unsafe: *assemblySlot = move assembly ..
        ..
    ..
    assemblyWaitStartTick := time.ticks()
    for i := 0 to assemblyFutures.count():
        assembly := try assemblyFutures.get(i)
        result := try assembly.await()
        if result.nok():
            throw result
        ..
    ..
    assemblyWaitElapsedMs := time.elapsedMs(assemblyWaitStartTick)
    linkStartTick := time.ticks()
    try llvm_cache.linkModules(addrof cache, checkedFiles, flagOpt, flagThreads)
    linkElapsedMs := time.elapsedMs(linkStartTick)

    try gl.startLog(log.LogLevel.DEBUG).writeLn("after link modules").end()

    elapsedTotalMs := time.elapsedMs(startTicks)
    backendElapsedMs := time.elapsedMs(backendStartTick)
    unmeasuredMs := elapsedTotalMs - (pipelineElapsedMs + checkElapsedMs + backendElapsedMs)

    if flagTimings:
        try printTimings(pipelineElapsedMs, checkElapsedMs, cacheLookupElapsedMs, loweringElapsedMs, assemblyWaitElapsedMs, linkElapsedMs, backendElapsedMs, unmeasuredMs, elapsedTotalMs)
    ..
    if flagTimingsPerFile:
        try printTimingsPerFile(f)
    ..

    # TODO: collect and merge 
    ret pipeErr.code()
..

sort(a u64, b u64) i64:
    if a < b: ret -1 ..
    if a > b: ret 1 ..
    ret 0
..

printTimings(pipelineElapsedMs u64, checkElapsedMs u64, cacheLookupElapsedMs u64, loweringElapsedMs u64, assemblyWaitElapsedMs u64, linkElapsedMs u64, backendElapsedMs u64, unmeasuredMs u64, elapsedTotalMs u64) !void:
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

printTimingsPerFile(root fctx.FileCtx*) !void:
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
