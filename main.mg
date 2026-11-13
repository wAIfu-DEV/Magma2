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

use "src/helper/logger" log
use "src/shared/token_types" tkt
use "src/shared/comperr" comperr
use "src/shared/origin" org
use "src/make_absolute" mk_abs

use "src/shared/global" gl
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

    flagOpt u64
    flags.unsigned("opt", 'O', addrof flagOpt, "optimization level used by LLVM, default is -O3")

    flagTimings bool # TODO: implement
    flags.boolean("timings", 'T', addrof flagTimings, "prints timings for each steps of the compilation")

    flagDebug bool
    flags.boolean("debug", 'd', addrof flagDebug, "prints additional debug logs")

    flagVerbose bool
    flags.boolean("verbose", 'V', addrof flagVerbose, "prints more logs than --debug")

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

    flagHelp bool # TODO: implement
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
    ctx = context.new(allocator, tp.executor())

    stdout := try io.stdout()
    defer stdout.close()

    defer tp.close()

    # ------------- #
    # FLAG HANDLING #
    # ------------- #

    if flagHelp || args.count() == 1:
        try flags.writeUsage(stdout.protoBorrow())
        ret 0
    ..

    logLevel := log.LogLevel.DEFAULT
    if flagVerbose:
        logLevel = log.LogLevel.VERBOSE
    elif flagDebug:
        logLevel = log.LogLevel.DEBUG
    ..

    gl.logger = log.new(stdout.writer(), logLevel)

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
    
    # ---------- #
    # INPUT FILE #
    # ---------- #

    gl.cwd = try fs.currentDir()
    stdRootParts := [2]str(gl.cwd, "std")
    gl.stdLibRoot = try path.join(stdRootParts)

    # startLog returns a writer and locks the stdout for other threads until .end is called
    # this keeps printed lines uninterrupted by concurrent writes
    try gl.startLog(log.LogLevel.DEBUG).write("CWD ").writeLn(gl.cwd).end()

    absolute := try mk_abs.makeAbsolute(filePath, "")
    defer absolute.free()

    try gl.startLog(log.LogLevel.DEBUG).write("PATH ").writeLn(absolute).end()

    fileCtx := try opf.openFile(absolute)
    f := addrof fileCtx

    try gl.startLog(log.LogLevel.DEBUG).write("SETUP ").writeUint64(time.elapsedUs(startTicks)).writeLn("µs").end()

    # -------------- #
    # PIPELINE START #
    # -------------- #

    # future is akin to JS's Promise but uses the context's executor, here the thread pool
    future := try pipe.pipelineAsync(f)

    gl.lockPipelines.lock()
    try gl.pipelines.setBorrowed(absolute, future)
    gl.lockPipelines.unlock()

    pipeErr := try future.await()

    # once main pipe is done, it waits for other pipes to finish
    loop gl.runningPipelines.load() > 0:
        thread.yield() # yields to OS
    ..

    try gl.startLog(log.LogLevel.DEFAULT).write("Compilation finished in: ").writeUint64(time.elapsedMs(startTicks)).writeLn("ms").end()

    # TODO: collect and merge 
    ret pipeErr.code()
..
