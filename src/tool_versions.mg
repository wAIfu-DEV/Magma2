mod tool_versions

# Probe for llvm tooling versions, used for cache fingerprinting
# @author codex (GPT6 Luna)

use "std:process" proc
use "std:strings" strings
use "std:errors" errors
use "std:future" fut
use "shared/global" gl

pub ToolVersions(
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

pub startToolVersionProbe() !$fut.Future[str]:
    ret try fut.new[str, bool](ctx.exec, runToolVersionProbe, true)
..

pub awaitToolVersion(value $fut.Future[str]) !$str:
    ret try value.await()
..

awaitAndFreeToolVersion(value $fut.Future[str]) !bool:
    output := try awaitToolVersion(move value)
    output.free()
    ret true
..

pub discardToolVersionFuture(value $fut.Future[str]) void:
    drained bool, awaitError error = awaitAndFreeToolVersion(move value)
    drained = drained
    awaitError = awaitError
..

pub decodeToolVersions(encoded str) !$ToolVersions:
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

