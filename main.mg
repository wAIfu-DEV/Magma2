mod main

# Entrypoint of the frontend, responsible for orchestration and flag handling
# @author devan
# @author codex (GPT6 Luna)

use "std:io" io
use "std:fs" fs
use "std:cast" cast
use "std:path" path
use "std:time" time
use "std:thread" thread
use "std:thread_pool" thread_pool
use "std:executor" executor
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

CompilerFlags(
    threadCnt u64
    optLevel u64
    timings bool
    timingsPerFile bool
    debug bool
    verbose bool
    explainCache bool
    version bool
    run bool
    output str
    input str
    emit str
    help bool
    naked bool
)

pub main(args str[]) !u32:
    startTicks := time.ticks()

    allocator := heap.allocator()

    # ----------- #
    # ARG PARSING #
    # ----------- #

    flags := CompilerFlags(
        threadCnt=0
        optLevel=3
        timings=false
        timingsPerFile=false
        debug=false
        verbose=false
        explainCache=false
        version=false
        run=false
        output=""
        input=""
        emit="exe"
        help=false
        naked=false
    )

    flagsParser := try flag.new(allocator, "magma")
    defer flagsParser.free()

    flagsParser.unsigned("threads",        't', addrof flags.threadCnt,      "maximum allowed concurrent threads for compilation, default -t0 (cpu core count)")
    flagsParser.unsigned("opt",            'O', addrof flags.optLevel,       "optimization level used by LLVM for executable and IR output, default is -O3")
    flagsParser.boolean( "timings",        'T', addrof flags.timings,        "prints timings for each steps of the compilation")
    flagsParser.boolean( "timings-per-file", 0, addrof flags.timingsPerFile, "prints lex, parse and check timings for each file")
    flagsParser.boolean( "debug",          'd', addrof flags.debug,          "prints additional debug logs")
    flagsParser.boolean( "verbose",        'V', addrof flags.verbose,        "prints more logs than --debug")
    flagsParser.boolean( "explain-cache",    0, addrof flags.explainCache,   "prints the cache decision and miss reason for each module")
    flagsParser.boolean( "version",        'v', addrof flags.version,        "prints the compiler's version, does not proceed with compilation")
    flagsParser.boolean( "run",            'r', addrof flags.run,            "runs the executable after compilation")
    flagsParser.string(  "output",         'o', addrof flags.output,         "path to the output the compiler will write to")
    flagsParser.string(  "input",          'i', addrof flags.input,          "path to the input magma file, alternative to positional arg")
    flagsParser.string(  "emit",           'e', addrof flags.emit,           "what type of output the compiler should write ('exe','llvm') default is 'exe'")
    flagsParser.boolean( "help",           'h', addrof flags.help,           "prints the available args for magma")
    flagsParser.boolean( "naked",            0, addrof flags.naked,          "use NullAllocator and SingleThreadExecutor as the program default context")

    flagRes := try flagsParser.parse(args)
    defer flagRes.free()

    emitExecutable := flags.emit == "exe"
    emitLLVM := flags.emit == "llvm"
    if emitExecutable == false && emitLLVM == false:
        throw errors.invalidArgument("--emit must be either 'exe' or 'llvm'")
    ..
    if flags.output == "":
        if emitLLVM:
            flags.output = "out.ll"
        else:
            flags.output = "out"
        ..
    ..
    if flags.run && emitLLVM:
        throw errors.invalidArgument("--run cannot be used with --emit llvm")
    ..

    # ------------ #
    # CONTEXT INIT #
    # ------------ #

    cores := cpu.coreCount()
    if flags.threadCnt != 0:
        cores = flags.threadCnt
    ..
    minCores u64 = 1

    scheduler := executor.singleThread()

    # ThreadPool needs stable storage
    tp thread_pool.ThreadPool* = try allocator.allocT[thread_pool.ThreadPool](1)
    defer allocator.free(tp)

    if cores > 1:
        unsafe *tp = try thread_pool.new(allocator, minCores, cores, 512, minCores) # TODO: 512 might be an issue, have to check
        scheduler = tp.executor()
    else:
        unsafe *tp = thread_pool.ThreadPool(state=none)
    ..
    defer tp.closeIfActive()

    ctx = context.new(allocator, scheduler)

    gl.stdin = try io.stdin()
    gl.stdout = try io.stdout()

    defer gl.stdout.flush()

    if flags.version:
        try gl.stdout.writeLn(compiler_version.VERSION)
        ret 0
    ..

    # ------------- #
    # FLAG HANDLING #
    # ------------- #

    if flags.help || args.count() == 1:
        try flagsParser.writeUsage(gl.stdout.writer())
        ret 0
    ..

    logLevel log.LogLevel = .DEFAULT
    if flags.verbose:
        logLevel = .VERBOSE
    elif flags.debug:
        logLevel = .DEBUG
    ..

    gl.logger = log.new(gl.stdout.writer(), logLevel)

    posArgs := flagRes.positionals()
    posArgsCnt := posArgs.count()

    filePath str
    if posArgsCnt <= 1 && flags.input == "":
        throw errors.invalidArgument("missing positional argument or --input flag for the input magma file")
    elif posArgsCnt > 2:
        throw errors.invalidArgument("cannot have more than 1 positional argument")
    elif flags.input != "":
        filePath = flags.input
    else: # count == 2
        unsafe filePath = posArgs[1]
    ..

    # --------- #
    # DATA INIT #
    # --------- #

    try gl.initGlobal()
    gl.naked = flags.naked

    try gl.startLog(.DEBUG)
        .writeLn("# DATA INIT")
        .end()

    # initialize required pipeline data
    try tkt.initKwMap()
    pipe.setupRunner()  # used to prevent circular deps in pipeline
                        # since parser calls
                        # TODO: delete the concept of circular deps

    # ---------- #
    # INPUT FILE #
    # ---------- #

    try gl.startLog(.DEBUG)
        .writeLn("# INPUT FILE")
        .end()

    gl.cwd = try fs.currentDir()
    gl.stdLibRoot = try path.join([]str(gl.cwd, "std"))

    # startLog returns a writer and locks the stdout for other threads until .end is called
    # this keeps printed lines uninterrupted by concurrent writes
    try gl.startLog(.DEBUG)
        .write("CWD ")
        .writeLn(gl.cwd)
        .end()

    absolute := try mk_abs.makeAbsolute(filePath, "")
    defer absolute.free()
    gl.mainUniqueName = try strings.copy(absolute)

    try gl.startLog(.DEBUG)
        .write("PATH ")
        .writeLn(absolute)
        .end()

    fileCtx := try opf.openFile(absolute)
    f := addrof fileCtx

    if true:
        gl.lockFiles.lock()
        defer gl.lockFiles.unlock()
        try gl.files.setBorrowed(absolute, f)
    ..

    try gl.startLog(.DEBUG)
        .write("SETUP ")
        .writeUint64(time.elapsedUs(startTicks))
        .writeLn("µs")
        .end()

    # ---------------------- #
    # MULTITHREADED PIPELINE #
    # ---------------------- #

    try gl.startLog(.DEBUG)
        .writeLn("# MULTITHREADED PIPELINE")
        .end()

    pipelineStartTick := time.ticks()

    # Futures use the selected executor: caller-thread execution at -t1, thread pool otherwise.
    future := try pipe.pipelineAsync(f)
    toolVersionFuture, toolLaunchError := tools.startToolVersionProbe()
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

    try gl.startLog(.DEBUG)
        .writeLn("after multithreaded pipeline")
        .end()

    # ----------------------------- #
    # SYNC SEMANTIC AND TYPE CHECKS #
    # ----------------------------- #

    checkStart := time.ticks()
    semanticErr := try pipe.checkGraph(f)
    checkElapsedMs := time.elapsedMs(checkStart)
    if semanticErr.nok():
        throw semanticErr
    ..

    try gl.startLog(.DEBUG)
        .writeLn("after semcheck")
        .end()

    # ------------- #
    # BITCODE CACHE #
    # ------------- #

    backendStartTick := time.ticks()
    cacheLookupStartTick := time.ticks()

    cacheVersion := try helpers.getCacheVersion(addrof toolVersions)
    defer cacheVersion.free()
    cache := try llvm_cache.open(gl.cwd, cacheVersion, compiler_version.TARGET_TRIPLE)
    defer cache.close()

    if flags.explainCache:
        cacheLocation := try path.join([]str(gl.cwd, ".magma"))
        defer cacheLocation.free()
        try gl.startLog(.DEFAULT)
            .write("LLVM cache: ")
            .writeLn(cacheLocation)
            .end()
        
        if cache.discardedIncompatible:
            try gl.startLog(.DEFAULT)
                .writeLn("LLVM cache namespace discarded: compiler or LLVM version changed")
                .end()
        ..
    ..

    # Resolve all module cache entries only after the complete graph has been
    # checked. The backend receives dependencies first, matching link order.
    checkedFiles := try pipe.collectCheckedGraph(f)
    pendingModules := try backend.resolveCacheLookups(checkedFiles, addrof cache, flags.explainCache, f.path, flags.debug)
    defer pendingModules.free()

    try gl.startLog(.DEBUG)
        .writeLn("after resolve cache")
        .end()

    cacheLookupElapsedMs := time.elapsedMs(cacheLookupStartTick)

    # ----------------------- #
    # IR LOWERING AND BACKEND #
    # ----------------------- #

    loweringTimings := try backend.lowerPendingModules(addrof pendingModules, addrof cache, flags.optLevel, flags.debug, flags.verbose, f.path, flags.debug)
    loweringElapsedMs := loweringTimings.loweringMs
    assemblyWaitElapsedMs := loweringTimings.assemblyWaitMs

    linkOutput := try path.join([]str(gl.cwd, flags.output))
    defer linkOutput.free()
    linkStartTick := time.ticks()
    if emitLLVM:
        try llvm_cache.linkModulesToIR(addrof cache, checkedFiles, flags.optLevel, linkOutput)
    else:
        try llvm_cache.linkModules(addrof cache, checkedFiles, flags.optLevel, cores, linkOutput, true)
    ..
    linkElapsedMs := time.elapsedMs(linkStartTick)

    try gl.startLog(.DEBUG)
        .writeLn("after link modules")
        .end()

    elapsedTotalMs := time.elapsedMs(startTicks)
    backendElapsedMs := time.elapsedMs(backendStartTick)
    unmeasuredMs := elapsedTotalMs - (pipelineElapsedMs + checkElapsedMs + backendElapsedMs)

    if flags.timings:
        try timings.printTimings(pipelineElapsedMs, checkElapsedMs, cacheLookupElapsedMs, loweringElapsedMs, assemblyWaitElapsedMs, linkElapsedMs, backendElapsedMs, unmeasuredMs, elapsedTotalMs)
    ..
    if flags.timingsPerFile:
        try timings.printTimingsPerFile(f)
    ..

    if flags.run:
        try gl.stdout.flush()
        runCode := try proc.exec(linkOutput, []str())
        ret runCode
    ..

    ret pipeErr.code()
..

