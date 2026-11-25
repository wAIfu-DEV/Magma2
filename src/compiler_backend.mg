mod compiler_backend

use "std:time" time
use "std:errors" errors
use "std:strings" strings
use "std:stable_list" stable
use "std:future" fut
use "helper/logger" log
use "shared/global" gl
use "shared/filectx" fctx
use "llvm_cache" llvm_cache
use "llvm_cache_fingerprint" llvm_cache_fingerprint
use "llvm_lowering" llvm_lowering

pub BackendWork(
    file fctx.FileCtx*
    loweringInputs str
    llvmText str
)

pub LoweringTimings(
    loweringMs u64
    assemblyWaitMs u64
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
    visibleFingerprint str*
    result str*
)

LoweringWork(
    work BackendWork*
    isMainPackage bool
    traceErrors bool
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
    unsafe: *work.result = try llvm_cache_fingerprint.loweringInputsFingerprint(work.file, work.cache, *work.visibleFingerprint) ..
    ret errors.ok()
..

runLowering(work LoweringWork*) !error:
    unsafe: work.work.llvmText = try llvm_lowering.emitModule(work.work.file, work.isMainPackage, work.traceErrors) ..
    ret errors.ok()
..

markLoweringRole(file fctx.FileCtx*, mainFilePath str, fingerprint str*, traceErrors bool) !void:
    role := "\nmodule-unit-v1"
    if strings.compare(file.path, mainFilePath):
        role = "\nmain-package-v1"
    ..
    if traceErrors:
        role = try strings.concat(role, "\nerror-traces-v1")
    else:
        role = try strings.concat(role, "\nerror-traces-disabled-v1")
    ..
    defer role.free()
    tagged := try strings.concat(*fingerprint, role)
    unsafe:
        fingerprint.free()
        *fingerprint = move tagged
    ..
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

pub resolveCacheLookups(
    checkedFiles fctx.FileArray
    cache llvm_cache.Cache*
    flagExplainCache bool
    mainFilePath str
    traceErrors bool
) !$stable.StableList[BackendWork]:
    pendingModules := try stable.new[BackendWork](ctx.alloc, none)
    onerror pendingModules.free()
    fingerprintCache := try llvm_cache_fingerprint.newFingerprintCache()
    defer fingerprintCache.close()
    visibleFingerprint := try llvm_cache_fingerprint.visibleImplementationsFingerprint()
    defer visibleFingerprint.free()
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
        for i := 0 to checkedFiles.count(): try interfaceFutures.push(fut.Future[error](state=none)) ..
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
        for i := 0 to checkedFiles.count(): try loweringFutures.push(fut.Future[error](state=none)) ..
        for i := 0 to checkedFiles.count():
            moduleFile := try checkedFiles.get(i)
            resultSlot := try loweringFingerprints.get(i)
            futureSlot := try loweringFutures.get(i)
            pending := try fut.new[error, LoweringFingerprintWork](ctx.exec, runLoweringFingerprint, LoweringFingerprintWork(file=moduleFile, cache=addrof fingerprintCache, visibleFingerprint=addrof visibleFingerprint, result=resultSlot))
            unsafe: *futureSlot = move pending ..
        ..
        for i := 0 to checkedFiles.count():
            fingerprintResult, fingerprintError := (try loweringFutures.get(i)).await()
            if fingerprintError.nok(): throw fingerprintError ..
            if fingerprintResult.nok(): throw fingerprintResult ..
            moduleFile := try checkedFiles.get(i)
            fingerprint := try loweringFingerprints.get(i)
            try markLoweringRole(moduleFile, mainFilePath, fingerprint, traceErrors)
        ..
        for i := 0 to checkedFiles.count(): try lookupFutures.push(fut.Future[error](state=none)) ..
        for i := 0 to checkedFiles.count():
            moduleFile := try checkedFiles.get(i)
            resultSlot := try lookupResults.get(i)
            fingerprint := try loweringFingerprints.get(i)
            work := CacheLookupWork(cache=cache, file=moduleFile, fingerprint=fingerprint, result=resultSlot)
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
            fingerprint := try llvm_cache_fingerprint.loweringInputsFingerprint(moduleFile, addrof fingerprintCache, visibleFingerprint)
            unsafe: *resultSlot = move fingerprint ..
        ..
        for i := 0 to checkedFiles.count():
            try markLoweringRole(try checkedFiles.get(i), mainFilePath, try loweringFingerprints.get(i), traceErrors)
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
            unsafe: *cached = try llvm_cache.lookupRecover(cache, moduleFile, *fingerprint) ..
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
            unsafe: try pendingModules.push(BackendWork(file=moduleFile, loweringInputs=try strings.copy(*fingerprint), llvmText="")) ..
        ..
    ..
    ret move pendingModules
..

newLoweringFutures(count u64) !$stable.StableList[fut.Future[error]]:
    futures := try stable.new[fut.Future[error]](ctx.alloc, cleanupLoweringFuture)
    onerror futures.free()
    for i := 0 to count:
        try futures.push(fut.Future[error](state=none))
    ..
    ret move futures
..

newAssemblyFutures(count u64) !$stable.StableList[fut.Future[error]]:
    futures := try stable.new[fut.Future[error]](ctx.alloc, cleanupAssemblyFuture)
    onerror futures.free()
    for i := 0 to count:
        try futures.push(fut.Future[error](state=none))
    ..
    ret move futures
..

pub lowerPendingModules(
    pendingModules stable.StableList[BackendWork]*
    cache llvm_cache.Cache*
    flagOpt u64
    flagDebug bool
    flagVerbose bool
    mainFilePath str
    traceErrors bool
) !$LoweringTimings:
    assemblyFutures := try newAssemblyFutures(pendingModules.count())
    defer assemblyFutures.free()
    loweringElapsedMs u64 = 0
    if PARALLEL_MODULE_LOWERING:
        lowerFutures := try newLoweringFutures(pendingModules.count())
        defer lowerFutures.free()
        loweringStartTick := time.ticks()
        for i := 0 to pendingModules.count():
            work := try pendingModules.get(i)
            if flagDebug || flagVerbose:
                try gl.startLog(log.LogLevel.DEBUG).write("LLVM LOWER ").writeLn(work.file.path).end()
            ..
            lowerFuture := try fut.new[error, LoweringWork](ctx.exec, runLowering, LoweringWork(work=work, isMainPackage=strings.compare(work.file.path, mainFilePath), traceErrors=traceErrors))
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
            assembly := try llvm_cache.assembleAsync(cache, work.file, work.loweringInputs, work.llvmText, flagOpt)
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
            work.llvmText = try llvm_lowering.emitModule(work.file, strings.compare(work.file.path, mainFilePath), traceErrors)
            loweringElapsedMs = loweringElapsedMs + time.elapsedMs(loweringStartTick)
            assembly := try llvm_cache.assembleAsync(cache, work.file, work.loweringInputs, work.llvmText, flagOpt)
            unsafe: *assemblySlot = move assembly ..
        ..
    ..
    assemblyWaitStartTick := time.ticks()
    for i := 0 to assemblyFutures.count():
        assembly := try assemblyFutures.get(i)
        result := try assembly.await()
        if result.nok(): throw result ..
    ..
    ret LoweringTimings(loweringMs=loweringElapsedMs, assemblyWaitMs=time.elapsedMs(assemblyWaitStartTick))
..

cleanupAssemblyFuture(value $fut.Future[error]) void:
    # Futures can still be publishing cache entries when later module lowering
    # fails. StableList cleanup runs before the cache and pending work defers.
    result, awaitError := value.await()
    result = result
    awaitError = awaitError
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




