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
use "std:fmt" fmt
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
use "src/compiler_backend" backend
use "src/tool_versions" tools
use "src/compiler_helpers" helpers
use "src/compiler_timings" timings

use "src/shared/global" gl
use "src/shared/filectx" fctx
use "src/lexer" lx
use "src/open_file" opf
use "src/parser" parser
use "src/node_printer" node_printer
use "src/pipeline" pipe

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

    flagVersion bool
    flags.boolean("version", 'v', addrof flagVersion, "prints the compiler's version, does not proceed with compilation")

    flagRun bool
    flags.boolean("run", 'r', addrof flagRun, "runs the executable after compilation")

    flagOut str = "out"
    flags.string("output", 'o', addrof flagOut, "path to the output the compiler will write to")

    flagIn str
    flags.string("input", 'i', addrof flagIn, "path to the input magma file, alternative to positional arg")

    flagEmit str = "exe"
    flags.string("emit", 'e', addrof flagEmit, "what type of output the compiler should write ('exe','llvm') default is 'exe'")

    flagHelp bool
    flags.boolean("help", 'h', addrof flagHelp, "prints the available args for magma")

    flagRes := try flags.parse(args)
    defer flagRes.free()

    emitExecutable := strings.compare(flagEmit, "exe")
    emitLLVM := strings.compare(flagEmit, "llvm")
    if emitExecutable == false && emitLLVM == false:
        throw errors.invalidArgument("--emit must be either 'exe' or 'llvm'")
    ..
    if flagRun && emitLLVM:
        throw errors.invalidArgument("--run cannot be used with --emit llvm")
    ..

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
        try gl.stdout.writer().writeLn(compiler_version.VERSION)
        try gl.stdout.flush()
        ret 0
    ..

    # ------------- #
    # FLAG HANDLING #
    # ------------- #

    if flagHelp || args.count() == 1:
        try flags.writeUsage(gl.stdout.writer())
        try gl.stdout.flush()
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

    try gl.initGlobal()
    try gl.startLog(log.LogLevel.DEBUG).writeLn("# DATA INIT").end()

    # initialize required pipeline data
    try tkt.initKwMap()
    pipe.setupRunner()  # used to prevent circular deps in pipeline
                        # since parser calls
                        # TODO: delete the concept of circular deps

    # ---------- #
    # INPUT FILE #
    # ---------- #

    try gl.startLog(log.LogLevel.DEBUG).writeLn("# INPUT FILE").end()

    gl.cwd = try fs.currentDir()
    gl.stdLibRoot = try path.join([]str(gl.cwd, "std"))

    # startLog returns a writer and locks the stdout for other threads until .end is called
    # this keeps printed lines uninterrupted by concurrent writes
    try gl.startLog(log.LogLevel.DEBUG).write("CWD ").writeLn(gl.cwd).end()

    absolute := try mk_abs.makeAbsolute(filePath, "")
    defer absolute.free()
    gl.mainUniqueName = try strings.copy(absolute)

    try gl.startLog(log.LogLevel.DEBUG).write("PATH ").writeLn(absolute).end()

    fileCtx := try opf.openFile(absolute)
    f := addrof fileCtx

    gl.lockFiles.lock()
    onerror gl.lockFiles.unlock()
    try gl.files.setBorrowed(absolute, f)
    gl.lockFiles.unlock()

    try gl.startLog(log.LogLevel.DEBUG).write("SETUP ").writeUint64(time.elapsedUs(startTicks)).writeLn("µs").end()

    # ---------------------- #
    # MULTITHREADED PIPELINE #
    # ---------------------- #

    try gl.startLog(log.LogLevel.DEBUG).writeLn("# MULTITHREADED PIPELINE").end()

    pipelineStartTick := time.ticks()

    # future is akin to JS's Promise but uses the context's executor, here the thread pool
    future := try pipe.pipelineAsync(f)
    toolVersionFuture fut.Future[str], toolLaunchError error = tools.startToolVersionProbe()
    if toolLaunchError.nok():
        helpers.discardErrorFuture(move future)
        throw toolLaunchError
    ..

    gl.lockPipelines.lock()
    registered bool, registerError error = helpers.registerRootPipeline(absolute, future)
    gl.lockPipelines.unlock()
    if registerError.nok():
        helpers.discardErrorFuture(move future)
        tools.discardToolVersionFuture(move toolVersionFuture)
        throw registerError
    ..

    pipeErr error, pipeFutureError error = future.await()

    # once main pipe is done, it waits for other pipes to finish
    loop gl.runningPipelines.load() > 0:
        thread.yield() # yields to OS scheduler
    ..

    toolVersionOutput := try tools.awaitToolVersion(move toolVersionFuture)
    defer toolVersionOutput.free()

    if pipeFutureError.nok(): throw pipeFutureError ..
    if pipeErr.nok(): throw pipeErr ..

    toolVersions := try tools.decodeToolVersions(toolVersionOutput)
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

    # ------------- #
    # BITCODE CACHE #
    # ------------- #

    backendStartTick := time.ticks()
    cacheLookupStartTick := time.ticks()

    # Cache validation belongs after the complete checked graph and before any
    # module lowering.
    llvmAsVersion := try strings.concat("\nllvm-as:\n", toolVersions.llvmVersionText)
    defer llvmAsVersion.free()
    optVersionPrefix := try strings.concat(llvmAsVersion, "\nopt:\n")
    defer optVersionPrefix.free()
    optVersion := try strings.concat(optVersionPrefix, toolVersions.optVersionText)
    defer optVersion.free()
    clangVersionPrefix := try strings.concat(optVersion, "\nclang:\n")
    defer clangVersionPrefix.free()
    toolVersionText := try strings.concat(clangVersionPrefix, toolVersions.clangVersionText)
    defer toolVersionText.free()
    cacheVersion := try strings.concat(compiler_version.VERSION, toolVersionText)
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
    pendingModules := try backend.resolveCacheLookups(checkedFiles, addrof cache, flagExplainCache, f.path, flagDebug)
    defer pendingModules.free()

    try gl.startLog(log.LogLevel.DEBUG).writeLn("after resolve cache").end()
    cacheLookupElapsedMs := time.elapsedMs(cacheLookupStartTick)

    # ----------------------- #
    # IR LOWERING AND BACKEND #
    # ----------------------- #

    loweringTimings := try backend.lowerPendingModules(addrof pendingModules, addrof cache, flagOpt, flagDebug, flagVerbose, f.path, flagDebug)
    loweringElapsedMs := loweringTimings.loweringMs
    assemblyWaitElapsedMs := loweringTimings.assemblyWaitMs

    linkOutput := try path.join([]str(gl.cwd, flagOut))
    defer linkOutput.free()
    linkStartTick := time.ticks()
    if emitLLVM:
        try llvm_cache.linkModulesToIR(addrof cache, checkedFiles, linkOutput)
    else:
        try llvm_cache.linkModules(addrof cache, checkedFiles, flagOpt, cores, linkOutput, true)
    ..
    linkElapsedMs := time.elapsedMs(linkStartTick)

    try gl.startLog(log.LogLevel.DEBUG).writeLn("after link modules").end()

    elapsedTotalMs := time.elapsedMs(startTicks)
    backendElapsedMs := time.elapsedMs(backendStartTick)
    unmeasuredMs := elapsedTotalMs - (pipelineElapsedMs + checkElapsedMs + backendElapsedMs)

    if flagTimings:
        try timings.printTimings(pipelineElapsedMs, checkElapsedMs, cacheLookupElapsedMs, loweringElapsedMs, assemblyWaitElapsedMs, linkElapsedMs, backendElapsedMs, unmeasuredMs, elapsedTotalMs)
    ..
    if flagTimingsPerFile:
        try timings.printTimingsPerFile(f)
    ..

    if flagRun:
        try gl.stdout.flush()
        runCode := try proc.exec(linkOutput, []str())
        ret runCode
    ..

    # TODO: collect and merge 
    try gl.stdout.flush()
    ret pipeErr.code()
..

