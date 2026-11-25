mod llvm_cache

# Per-source bitcode cache. The front end remains authoritative: callers invoke
# lookup only after parsing/linking/checking the current graph.

use "std:fs" fs
use "std:path" path
use "std:strings" strings
use "std:sha1" sha1
use "std:slices" slices
use "std:strconv" strconv
use "std:cast" cast
use "std:builder" builder
use "std:process" proc
use "std:future" future
use "std:time" time
use "std:abort" abort
use "std:errors" errs
use "std:list" ls

use "shared/filectx" fctx

const SCHEMA str = "magma-bitcode-cache-v6"
const DIGEST_HEX_BYTES u64 = 40

pub Cache(
    root str
    identityRoot str
    version str
    targetTriple str
    discardedIncompatible bool
)

pub Lookup(
    hit bool
    bitcode str
    reason str
)

AssemblyWork(
    cache Cache*
    file fctx.FileCtx*
    interfaceFingerprint str
    llvmText str
    optimizationLevel u64
)


hexByte(value u8) u8:
    if value < 10:
        ret value + 48
    ..
    ret value - 10 + 97
..

digestHex(input u8[]) !$str:
    digest := try sha1.sum(input)
    defer slices.free(digest)
    output := try strings.alloc(DIGEST_HEX_BYTES)
    data := strings.toPtr(output)
    unsafe:
        for i u64 = 0 to 20:
            byte := digest[i]
            data[i * 2] = hexByte(byte >> 4)
            data[i * 2 + 1] = hexByte(byte & 15)
        ..
    ..
    ret move output
..

stringDigest(value str) !$str:
    input u8[] = slices.fromPtr(strings.toPtr(value), value.countBytes())
    ret try digestHex(input)
..

fixedUint(value u64) !$str:
    digits := try strconv.formatUint(value)
    defer digits.free()
    if digits.countBytes() > 20:
        throw "unsigned metadata value exceeds its fixed-width field"
    ..
    output := try builder.new()
    defer output.free()
    for i := digits.countBytes() to 20:
        try output.addByte(48)
    ..
    try output.appendBorrowed(digits)
    ret try output.build()
..

join2(left str, right str) !$str:
    ret try path.join([]str(left, right))
..

markerMatches(path str, version str) bool:
    prior str, readError error = fs.readFile(path)
    if readError.nok():
        prior.free()
        ret false
    ..
    defer prior.free()
    ret strings.compare(prior, version)
..

pub open(invocationCwd str, compilerVersion str, targetTriple str) !$Cache:
    cacheRoot := try join2(invocationCwd, ".magma")
    defer cacheRoot.free()
    currentVersionFile := try join2(cacheRoot, "compiler-version")
    defer currentVersionFile.free()
    currentInfo fs.Metadata, currentInfoError error = fs.metadata(currentVersionFile)
    discardedIncompatible := false
    if currentInfoError.ok():
        if markerMatches(currentVersionFile, compilerVersion) == false:
            discardedIncompatible = true
            # Invalidate old compiler/LLVM namespaces. A cleanup failure is
            # harmless: the versioned directory below cannot hit them.
            fs.removeTree(cacheRoot)
        ..
    ..
    try fs.makeDirs(cacheRoot)
    currentVersionTemp := try join2(cacheRoot, "compiler-version.tmp")
    defer currentVersionTemp.free()
    try fs.writeFile(currentVersionTemp, compilerVersion)
    try fs.replace(currentVersionTemp, currentVersionFile)
    versionDigest := try stringDigest(compilerVersion)
    defer versionDigest.free()
    namespace := try strings.concat("v-", versionDigest)
    defer namespace.free()
    root := try join2(cacheRoot, namespace)
    defer root.free()
    versionFile := try join2(root, "compiler-version")
    defer versionFile.free()
    try fs.makeDirs(root)
    modulesDir := try join2(root, "modules")
    defer modulesDir.free()
    try fs.makeDirs(modulesDir)
    thinLtoInputsDir := try join2(root, "thinlto-inputs")
    defer thinLtoInputsDir.free()
    try fs.makeDirs(thinLtoInputsDir)

    tempVersion := try join2(root, "compiler-version.tmp")
    defer tempVersion.free()
    try fs.writeFile(tempVersion, compilerVersion)
    try fs.replace(tempVersion, versionFile)
    rootCopy := try strings.copy(root)
    identityRoot str, identityError error = fs.canonicalize(invocationCwd)
    if identityError.nok():
        rootCopy.free()
        throw identityError
    ..
    ret Cache(root=move rootCopy, identityRoot=move identityRoot, version=try strings.copy(compilerVersion), targetTriple=try strings.copy(targetTriple), discardedIncompatible=discardedIncompatible)
..

destr Cache.close() !void:
    this.root.free()
    this.identityRoot.free()
    this.version.free()
    this.targetTriple.free()
..

sourceIdentity(cache Cache*, filePath str) !$str:
    canonical := try fs.canonicalize(filePath)
    defer canonical.free()
    rootLength := cache.identityRoot.countBytes()
    if canonical.countBytes() > rootLength:
        root := try strings.substring(cache.identityRoot, 0, rootLength)
        defer root.free()
        candidate := try strings.substring(canonical, 0, rootLength)
        defer candidate.free()
        rootSeparator := strings.byteAt(cache.identityRoot, rootLength - 1)
        separator := strings.byteAt(canonical, rootLength)
        rootHasSeparator := rootSeparator == 47 || rootSeparator == 92
        pathHasSeparator := separator == 47 || separator == 92
        if strings.compare(root, candidate) && (rootHasSeparator || pathHasSeparator):
            relativeStart := rootLength + 1
            if rootHasSeparator:
                relativeStart = rootLength
            ..
            relative := try strings.substring(canonical, relativeStart, canonical.countBytes())
            defer relative.free()
            ret try strings.concat("relative:", relative)
        ..
    ..
    ret try strings.concat("external:", canonical)
..

moduleId(cache Cache*, filePath str) !$str:
    identity := try sourceIdentity(cache, filePath)
    defer identity.free()
    ret try stringDigest(identity)
..

cacheFile(cache Cache*, module str, suffix str) !$str:
    modulesDir := try join2(cache.root, "modules")
    defer modulesDir.free()
    name := try strings.concat(module, suffix)
    defer name.free()
    ret try join2(modulesDir, name)
..

pub moduleBitcodePath(cache Cache*, file fctx.FileCtx*) !$str:
    module := try moduleId(cache, file.path)
    defer module.free()
    ret try cacheFile(cache, module, ".bc")
..

appendModuleLinkInput(output builder.Builder*, cache Cache*, file fctx.FileCtx*) !$str:
    try appendLinkField(output, file.path)
    bitcodePath := try moduleBitcodePath(cache, file)
    defer bitcodePath.free()
    bitcode := try fs.readFile(bitcodePath)
    defer bitcode.free()
    digest := try stringDigest(bitcode)
    defer digest.free()
    try appendLinkField(output, digest)
    ret try strings.copy(digest)
..

metaPrefix(cache Cache*, module str, file fctx.FileCtx*, interfaceFingerprint str) !$str:
    info := try fs.metadata(file.path)
    identity := try sourceIdentity(cache, file.path)
    defer identity.free()
    sourceDigest := try stringDigest(file.content)
    defer sourceDigest.free()
    size := try fixedUint(info.size())
    defer size.free()
    modified := try fixedUint(cast.itou(info.modified()))
    defer modified.free()

    output := try builder.new()
    defer output.free()
    try output.appendBorrowed(SCHEMA)
    try output.appendBorrowed("\n")
    try output.appendBorrowed(cache.version)
    try output.appendBorrowed("\n")
    try output.appendBorrowed(module)
    try output.appendBorrowed("\n")
    try output.appendBorrowed(identity)
    try output.appendBorrowed("\n")
    try output.appendBorrowed(size)
    try output.appendBorrowed("\n")
    try output.appendBorrowed(modified)
    try output.appendBorrowed("\n")
    try output.appendBorrowed(sourceDigest)
    try output.appendBorrowed("\n")
    try output.appendBorrowed(interfaceFingerprint)
    try output.appendBorrowed("\n")
    ret try output.build()
..

miss(reason str) !$Lookup:
    ret Lookup(hit=false, bitcode=try strings.alloc(0), reason=reason)
..

destr Lookup.close() void:
    this.bitcode.free()
..

removeQuietly(path str) void:
    # Cache cleanup is best-effort. A failed unlink must not prevent the
    # backend from rebuilding this module from the checked AST.
    fs.removeFile(path)
..

cleanupString(value $str) void:
    value.free()
..


appendLinkField(output builder.Builder*, value str) !void:
    length := try strconv.formatUint(value.countBytes())
    defer length.free()
    try output.appendCopy(length)
    try output.appendBorrowed(":")
    try output.appendCopy(value)
    try output.appendBorrowed(";")
..

thinLtoInputKey(cache Cache*, file fctx.FileCtx*, bitcodeDigest str, optimizationLevel u64) !$str:
    module := try moduleId(cache, file.path)
    defer module.free()
    optimization := try strconv.formatUint(optimizationLevel)
    defer optimization.free()
    keyData := try builder.new()
    defer keyData.free()
    try appendLinkField(addrof keyData, "magma-thinlto-input-v1")
    try appendLinkField(addrof keyData, module)
    try appendLinkField(addrof keyData, bitcodeDigest)
    try appendLinkField(addrof keyData, optimization)
    try appendLinkField(addrof keyData, cache.targetTriple)
    serialized := try keyData.build()
    defer serialized.free()
    ret try stringDigest(serialized)
..

prepareThinLtoInput(cache Cache*, file fctx.FileCtx*, bitcodeDigest str, sourcePath str, optimizationLevel u64) !$str:
    key := try thinLtoInputKey(cache, file, bitcodeDigest, optimizationLevel)
    defer key.free()
    name := try strings.concat(key, ".o")
    defer name.free()
    inputsDir := try join2(cache.root, "thinlto-inputs")
    defer inputsDir.free()
    preparedPath := try join2(inputsDir, name)
    defer preparedPath.free()
    cachedInfo fs.Metadata, cachedInfoError error = fs.metadata(preparedPath)
    if cachedInfoError.ok() && cachedInfo.size() > 0:
        ret try strings.copy(preparedPath)
    ..

    temporaryName := try strings.concat(key, ".tmp")
    defer temporaryName.free()
    temporaryPath := try join2(inputsDir, temporaryName)
    defer temporaryPath.free()
    removeQuietly(temporaryPath)
    optimization := try strconv.formatUint(optimizationLevel)
    defer optimization.free()
    optimizationFlag := try strings.concat("-O", optimization)
    defer optimizationFlag.free()
    arguments := []str("-Wno-override-module", "-target", cache.targetTriple, "-x", "ir", "-c", "-flto=thin", optimizationFlag, "-o", temporaryPath, sourcePath)
    exitCode := try proc.exec("clang", arguments)
    if exitCode != 0:
        removeQuietly(temporaryPath)
        throw "clang failed to prepare a cached ThinLTO module"
    ..
    try fs.replace(temporaryPath, preparedPath)
    ret try strings.copy(preparedPath)
..

appendPreparedThinLtoInput(arguments ls.List[str]*, cache Cache*, file fctx.FileCtx*, bitcodeDigest str, optimizationLevel u64) !void:
    bitcodePath := try moduleBitcodePath(cache, file)
    defer bitcodePath.free()
    prepared := try prepareThinLtoInput(cache, file, bitcodeDigest, bitcodePath, optimizationLevel)
    try arguments.pushRight(move prepared)
..

pub lookup(cache Cache*, file fctx.FileCtx*, interfaceFingerprint str) !$Lookup:
    module := try moduleId(cache, file.path)
    defer module.free()
    metaPath := try cacheFile(cache, module, ".meta")
    defer metaPath.free()
    bitcodePath := try cacheFile(cache, module, ".bc")
    defer bitcodePath.free()

    expected := try metaPrefix(cache, module, file, interfaceFingerprint)
    defer expected.free()
    metadata str, metaError error = fs.readFile(metaPath)
    if metaError.nok():
        # A partially written or unreadable entry must not survive as a
        # candidate for a later invocation. Treat all cache I/O faults as a
        # local miss; the checked source remains authoritative.
        removeQuietly(metaPath)
        removeQuietly(bitcodePath)
        ret try miss("metadata missing or unreadable")
    ..
    defer metadata.free()
    if metadata.countBytes() != expected.countBytes() + DIGEST_HEX_BYTES + 1:
        removeQuietly(metaPath)
        removeQuietly(bitcodePath)
        ret try miss("metadata is truncated")
    ..
    prefix := try strings.substring(metadata, 0, expected.countBytes())
    defer prefix.free()
    if strings.compare(prefix, expected) == false:
        # The lowering fingerprint may include a module-role suffix, so use
        # its actual length when locating the fixed-width source digest.
        interfaceStart := expected.countBytes() - interfaceFingerprint.countBytes() - 1
        sourceStart := interfaceStart - (DIGEST_HEX_BYTES + 1)
        storedSourceDigest := try strings.substring(metadata, sourceStart, sourceStart + DIGEST_HEX_BYTES)
        defer storedSourceDigest.free()
        storedInterfaceDigest := try strings.substring(metadata, interfaceStart, interfaceStart + DIGEST_HEX_BYTES)
        defer storedInterfaceDigest.free()
        currentSourceDigest := try stringDigest(file.content)
        defer currentSourceDigest.free()
        removeQuietly(metaPath)
        removeQuietly(bitcodePath)
        schemaLength := SCHEMA.countBytes()
        storedSchema := try strings.substring(metadata, 0, schemaLength)
        defer storedSchema.free()
        if strings.compare(storedSchema, SCHEMA) == false:
            ret try miss("cache schema mismatch")
        ..
        if strings.compare(storedSourceDigest, currentSourceDigest) == false:
            ret try miss("source content changed")
        ..
        if strings.compare(storedInterfaceDigest, interfaceFingerprint) == false:
            ret try miss("public dependency changed")
        ..
        ret try miss("cache schema, compiler, or source metadata changed")
    ..
    storedDigest := try strings.substring(metadata, expected.countBytes(), expected.countBytes() + DIGEST_HEX_BYTES)
    defer storedDigest.free()
    terminator := strings.byteAt(metadata, expected.countBytes() + DIGEST_HEX_BYTES)
    if terminator != 10:
        removeQuietly(metaPath)
        removeQuietly(bitcodePath)
        ret try miss("metadata digest is malformed")
    ..

    bitcode str, bitcodeError error = fs.readFile(bitcodePath)
    if bitcodeError.nok():
        removeQuietly(metaPath)
        removeQuietly(bitcodePath)
        ret try miss("bitcode missing or unreadable")
    ..
    actualDigest str, digestError error = stringDigest(bitcode)
    if digestError.nok():
        bitcode.free()
        throw digestError
    ..
    if strings.compare(actualDigest, storedDigest) == false:
        bitcode.free()
        actualDigest.free()
        removeQuietly(metaPath)
        removeQuietly(bitcodePath)
        ret try miss("bitcode checksum mismatch")
    ..
    actualDigest.free()

    # Do not run llvm-dis on cache hits: llvm-as and opt validate newly
    # generated bitcode before publication, and the stored digest detects
    # changes to a cached payload. Revalidating every hit added one subprocess
    # and a full bitcode parse per module without evidence that it helps.
    # decodedPath := try cacheFile(cache, module, ".verify.ll.tmp")
    # defer decodedPath.free()
    # arguments := []str("-o", decodedPath, bitcodePath)
    # verifier, verifierStartError := proc.execAsync("llvm-dis", arguments)
    # if verifierStartError.nok():
    #     removeQuietly(decodedPath)
    #     bitcode.free()
    #     removeQuietly(metaPath)
    #     removeQuietly(bitcodePath)
    #     ret try miss("LLVM bitcode validator could not be started")
    # ..
    # verifyCode, verifyError := verifier.await()
    # removeQuietly(decodedPath)
    # if verifyError.nok() || verifyCode != 0:
    #     bitcode.free()
    #     removeQuietly(metaPath)
    #     removeQuietly(bitcodePath)
    #     ret try miss("bitcode failed LLVM validation")
    # ..
    ret Lookup(hit=true, bitcode=move bitcode, reason="hit")
..

pub lookupRecover(cache Cache*, file fctx.FileCtx*, interfaceFingerprint str) !$Lookup:
    result, validationError := lookup(cache, file, interfaceFingerprint)
    if validationError.nok():
        module := try moduleId(cache, file.path)
        defer module.free()
        metadataPath := try cacheFile(cache, module, ".meta")
        defer metadataPath.free()
        bitcodePath := try cacheFile(cache, module, ".bc")
        defer bitcodePath.free()
        removeQuietly(metadataPath)
        removeQuietly(bitcodePath)
        ret try miss("cache validation failed; entry invalidated")
    ..
    ret move result
..

pub publish(cache Cache*, file fctx.FileCtx*, interfaceFingerprint str, bitcode str) !void:
    module := try moduleId(cache, file.path)
    defer module.free()
    metaPath := try cacheFile(cache, module, ".meta")
    defer metaPath.free()
    bitcodePath := try cacheFile(cache, module, ".bc")
    defer bitcodePath.free()
    metaTemp := try cacheFile(cache, module, ".meta.tmp")
    defer metaTemp.free()
    bitcodeTemp := try cacheFile(cache, module, ".bc.tmp")
    defer bitcodeTemp.free()

    expected := try metaPrefix(cache, module, file, interfaceFingerprint)
    defer expected.free()
    bitcodeDigest := try stringDigest(bitcode)
    defer bitcodeDigest.free()
    metadata := try strings.concat(expected, bitcodeDigest)
    defer metadata.free()
    terminated := try strings.concat(metadata, "\n")
    defer terminated.free()

    try fs.writeFile(bitcodeTemp, bitcode)
    try fs.replace(bitcodeTemp, bitcodePath)
    try fs.writeFile(metaTemp, terminated)
    try fs.replace(metaTemp, metaPath)
..

# Assemble one freshly lowered module and publish its verified bitcode. Callers
# can run this in a Future per module so independent llvm-as jobs overlap.
pub assembleAndPublish(cache Cache*, file fctx.FileCtx*, interfaceFingerprint str, llvmText str, optimizationLevel u64) !void:
    module := try moduleId(cache, file.path)
    defer module.free()
    llvmPath := try cacheFile(cache, module, ".ll.tmp")
    defer llvmPath.free()
    bitcodePath := try cacheFile(cache, module, ".assembled.bc.tmp")
    defer bitcodePath.free()
    summaryPath := try cacheFile(cache, module, ".thinlto.bc.tmp")
    defer summaryPath.free()

    try fs.writeFile(llvmPath, llvmText)
    arguments := []str("-o", bitcodePath, llvmPath)
    # This function runs inside one assembly Future. Use the synchronous child
    # wait here so a single-worker executor never blocks waiting on a nested
    # Future queued to that same executor.
    exitCode := try proc.exec("llvm-as", arguments)
    if exitCode != 0:
        removeQuietly(bitcodePath)
        removeQuietly(summaryPath)
        throw "llvm-as failed for a lowered module"
    ..
    summaryArguments := []str("-module-summary", "-o", summaryPath, bitcodePath)
    summaryCode := try proc.exec("opt", summaryArguments)
    if summaryCode != 0:
        removeQuietly(llvmPath)
        removeQuietly(bitcodePath)
        removeQuietly(summaryPath)
        throw "opt failed to add a ThinLTO module summary"
    ..
    bitcode := try fs.readFile(summaryPath)
    defer bitcode.free()
    try publish(cache, file, interfaceFingerprint, bitcode)
    bitcodeDigest := try stringDigest(bitcode)
    defer bitcodeDigest.free()
    prepared := try prepareThinLtoInput(cache, file, bitcodeDigest, summaryPath, optimizationLevel)
    prepared.free()
    removeQuietly(llvmPath)
    removeQuietly(bitcodePath)
    removeQuietly(summaryPath)
..

runAssemblyWork(work AssemblyWork*, signal abort.Signal) !error:
    try signal.check()
    try assembleAndPublish(work.cache, work.file, work.interfaceFingerprint, work.llvmText, work.optimizationLevel)
    ret errs.ok()
..

# Schedules independent module assembly on the same executor used by the
# front-end pipeline. The source FileCtx, cache, fingerprint, and IR text must
# remain alive until the returned future is awaited.
pub assembleAsync(cache Cache*, file fctx.FileCtx*, interfaceFingerprint str, llvmText str, optimizationLevel u64) !$future.Future[error]:
    work := AssemblyWork(cache=cache, file=file, interfaceFingerprint=interfaceFingerprint, llvmText=llvmText, optimizationLevel=optimizationLevel)
    ret try future.newAbort[error, AssemblyWork](ctx.exec, runAssemblyWork, work)
..

# Links the complete checked graph from independent bitcode units. Reuses the
# linked object when the ordered bitcode inputs and link settings match.
pub linkModulesToIR(cache Cache*, files fctx.FileArray, outputPath str) !void:
    arguments := try ls.new[str](ctx.alloc, cleanupString)
    defer arguments.free()
    try arguments.pushRight(try strings.copy("-S"))
    try arguments.pushRight(try strings.copy("-o"))
    try arguments.pushRight(try strings.copy(outputPath))
    for i := 0 to files.count():
        file := try files.get(i)
        bitcodePath := try moduleBitcodePath(cache, file)
        try arguments.pushRight(move bitcodePath)
    ..
    linker := try proc.execAsync("llvm-link", arguments.view())
    exitCode := try linker.await()
    if exitCode != 0:
        throw "llvm-link failed while producing LLVM IR"
    ..
..

pub linkModules(cache Cache*, files fctx.FileArray, optimizationLevel u64, threadCount u64, outputPath str, produceExecutable bool) !void:
    executable := "clang"
    linkInputBuilder := try builder.new()
    defer linkInputBuilder.free()
    try appendLinkField(addrof linkInputBuilder, "magma-thinlto-link-v5")
    linkMode := "relocatable"
    if produceExecutable:
        linkMode = "executable"
    ..
    try appendLinkField(addrof linkInputBuilder, linkMode)
    try appendLinkField(addrof linkInputBuilder, cache.targetTriple)
    optimization := try strconv.formatUint(optimizationLevel)
    defer optimization.free()
    try appendLinkField(addrof linkInputBuilder, optimization)
    thinLtoJobs := try strconv.formatUint(threadCount)
    defer thinLtoJobs.free()
    # Job count changes scheduling, not the module inputs or optimization
    # semantics, so it is forwarded to LLD but does not split link cache keys.
    linkInputDigests := try ls.new[str](ctx.alloc, cleanupString)
    defer linkInputDigests.free()
    for i := 0 to files.count():
        file := try files.get(i)
        digest := try appendModuleLinkInput(addrof linkInputBuilder, cache, file)
        try linkInputDigests.pushRight(move digest)
    ..
    linkInput := try linkInputBuilder.build()
    defer linkInput.free()
    linkKey := try stringDigest(linkInput)
    defer linkKey.free()
    keyedNamePrefix := try strings.concat("program-", linkKey)
    defer keyedNamePrefix.free()
    outputSuffix := ".o"
    if produceExecutable:
        outputSuffix = ".exe"
    ..
    keyedName := try strings.concat(keyedNamePrefix, outputSuffix)
    defer keyedName.free()
    cachedOutputPath := try join2(cache.root, keyedName)
    defer cachedOutputPath.free()
    temporaryName := try strings.concat(keyedNamePrefix, ".tmp")
    defer temporaryName.free()
    temporaryPath := try join2(cache.root, temporaryName)
    defer temporaryPath.free()
    cachedInfo fs.Metadata, cachedInfoError error = fs.metadata(cachedOutputPath)
    if cachedInfoError.ok() && cachedInfo.size() > 0:
        # Stage beside the destination and atomically replace it. Copying
        # directly truncates outputPath, which fails with ETXTBSY when this
        # compiler is itself running from the default output path ("out").
        outputTempSuffix := try strconv.formatUint(time.ticks())
        defer outputTempSuffix.free()
        outputTempName := try strings.concat(".magma-tmp-", outputTempSuffix)
        defer outputTempName.free()
        outputTempPath := try strings.concat(outputPath, outputTempName)
        defer outputTempPath.free()
        removeQuietly(outputTempPath)
        try fs.copyFile(cachedOutputPath, outputTempPath)
        try fs.replace(outputTempPath, outputPath)
        ret
    ..

    arguments := try ls.new[str](ctx.alloc, cleanupString)
    defer arguments.free()
    try arguments.pushRight(try strings.copy("-Wno-override-module"))
    try arguments.pushRight(try strings.copy("-flto=thin"))
    try arguments.pushRight(try strings.copy("-fuse-ld=lld"))
    thinLtoCachePath := try join2(cache.root, "thinlto")
    defer thinLtoCachePath.free()
    try fs.makeDirs(thinLtoCachePath)
    thinLtoCacheArgument := try strings.concat("-Wl,--thinlto-cache-dir=", thinLtoCachePath)
    defer thinLtoCacheArgument.free()
    try arguments.pushRight(try strings.copy(thinLtoCacheArgument))
    thinLtoJobsArgument := try strings.concat("-Wl,--thinlto-jobs=", thinLtoJobs)
    defer thinLtoJobsArgument.free()
    try arguments.pushRight(try strings.copy(thinLtoJobsArgument))
    if produceExecutable == false:
        try arguments.pushRight(try strings.copy("-r"))
    ..
    optimizationFlag := try strings.concat("-O", optimization)
    defer optimizationFlag.free()
    try arguments.pushRight(try strings.copy(optimizationFlag))
    try arguments.pushRight(try strings.copy("-o"))
    try arguments.pushRight(try strings.copy(outputPath))
    for i := 0 to files.count():
        file := try files.get(i)
        digest := try linkInputDigests.get(i)
        try appendPreparedThinLtoInput(addrof arguments, cache, file, digest, optimizationLevel)
    ..
    linker := try proc.execAsync(executable, arguments.view())
    exitCode := try linker.await()
    if exitCode != 0:
        throw "ThinLTO link failed while producing output"
    ..
    try fs.copyFile(outputPath, temporaryPath)
    try fs.replace(temporaryPath, cachedOutputPath)
..
