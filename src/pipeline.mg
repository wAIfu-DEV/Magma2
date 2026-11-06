mod pipeline

use "std:future" future
use "std:abort" abort
use "std:errors" errs
use "std:fmt" fmt
use "std:time" time

use "shared/filectx" fctx
use "lexer" lx
use "shared/global" gl
use "shared/token_types" tkt

# thin wrapper around file context, prevents copy
fw(
    f fctx.FileCtx*,
)

pipelineEntry(w fw*, a abort.Signal) !error:
    f := w.f

    lexStart := time.ticks()

    f.tokens = try lx.run(f)
    
    lexElapsedUs := time.elapsedUs(lexStart)
    fmt.str(ctx.alloc, "Magma lexer: ").uint(lexElapsedUs).str(" µs\n").print()

    for i := 0 to f.tokens.count():
        tk := try f.tokens.get(i)
        gl.logger.log(try tkt.getTkRepr(tk.type))
    
        if tk.kwType == tkt.KwType.NEWLINE:
            gl.logger.log("(newline)")
            gl.logger.log("\n")
        elif tk.type == tkt.TkType.KEYWORD:
            gl.logger.log("(")
            gl.logger.log(try tkt.getKwRepr(tk.kwType))
            gl.logger.log(") ")
        else:
            gl.logger.log("(")
            gl.logger.log(tk.repr)
            gl.logger.log(") ")
        ..
    ..

    ret errs.ok()
..

pub pipelineAsync(f fctx.FileCtx*) !$future.Future[error]:
    ret try future.newAbort[error, fw](ctx.exec, pipelineEntry, fw(f=f))
..

pub pipelineSync(f fctx.FileCtx*) !error:
    abctrl := try abort.new()
    defer abctrl.close()
    w := fw(f=f)
    ret try pipelineEntry(addrof w, abctrl.signal())
..
