mod compiler_helpers

# Helpers for main
# @author codex (GPT6 Luna)

use "std:future" fut
use "std:strings" strings

use "shared/global" gl
use "tool_versions" tools
use "compiler_version" compiler_version

pub discardErrorFuture(value $fut.Future[error]) void:
    output error, awaitError error = value.await()
    output = output
    awaitError = awaitError
..

pub registerRootPipeline(path str, future fut.Future[error]) !bool:
    try gl.pipelines.setBorrowed(path, future)
    ret true
..

pub getCacheVersion(toolVersions tools.ToolVersions*) !$str:
    # TODO: might be better to use a builder
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
    ret try strings.concat(compiler_version.VERSION, toolVersionText)
..