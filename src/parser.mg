mod parser

use "std:memory" mem
use "std:list" ls
use "std:array" arr
use "std:cast" cast
use "std:slices" slices
use "std:path" path
use "std:strings" strgs

use "shared/filectx" fctx
use "shared/token_types" tkt
use "shared/node_types" nt
use "shared/comperr" comperr
use "shared/origin" org
use "decl_resolver" decl
use "make_absolute" mk_abs
use "shared/global" gl
use "helper/logger" log

Parser(
    file fctx.FileCtx*,
    module decl.Module*,
    scope decl.Scope*,
    idx u64,
    currTokIdx u64,
    currTok tkt.Token,
    errors ls.List[comperr.CompErr],
    moduleSeen bool,
    pendingPublic bool,
    pendingGlobal bool,
    pendingConst bool,
    pendingNoCtx bool,
    pendingDestructor bool,
    pruneNext bool,
)

Parser.peek() !tkt.Token:
    if this.currTokIdx == this.idx && this.idx != 0:
        ret this.currTok
    ..
    this.currTokIdx = this.idx
    this.currTok = try this.file.tokens.get(this.currTokIdx)
    ret this.currTok
..

Parser.consume() void:
    this.idx = this.idx + 1
..

Parser.currPos() org.FilePos:
    ret this.currTok.pos
..

errorFatal(p Parser*, code str, msg str, help str, pos org.FilePos) !void:
    p.errors.pushRight(comperr.CompErr(
        sev=comperr.Severity.ERROR, code=code, msg=msg, help=help,
        file=p.file, org=org.Origin(filePath=p.file.path, position=pos),
    ))
    throw msg
..

nonFatalError(p Parser*, code str, msg str, help str, pos org.FilePos) !void:
    try p.errors.pushRight(comperr.CompErr(
        sev=comperr.Severity.ERROR, code=code, msg=msg, help=help,
        file=p.file, org=org.Origin(filePath=p.file.path, position=pos),
    ))
..

printErrors(p Parser*) !void:
    w := try gl.startLog(log.LogLevel.DEBUG)
    defer w.end()

    for i := 0 to p.errors.count():
        err, e := p.errors.get(i)
        if e.ok():
            err.log()
        ..
    ..
..

ensureTkType(p Parser*, tk tkt.Token, type tkt.TkType, msg str, help str) !void:
    if tk.type != type:
        try errorFatal(p, "UNEXPECTED_TOK", msg, help, tk.pos)
    ..
..

ensureKwType(p Parser*, tk tkt.Token, type tkt.KwType, msg str, help str) !void:
    if tk.kwType != type:
        try errorFatal(p, "UNEXPECTED_KEYW", msg, help, tk.pos)
    ..
..

parseType(p Parser*) !nt.Type*:
    owned := false
    throwing := false
    noContext := false
    loop true:
        prefix := try p.peek()
        if prefix.kwType == tkt.KwType.EXCLAM:
            throwing = true
            p.consume()
        elif prefix.kwType == tkt.KwType.DOLLAR:
            owned = true
            p.consume()
        elif prefix.kwType == tkt.KwType.NOCTX:
            noContext = true
            p.consume()
        else:
            break
        ..
    ..

    start := try p.peek()
    current nt.Type*
    if start.kwType == tkt.KwType.AT:
        p.consume()
        directive := try p.peek()
        try ensureTkType(p, directive, tkt.TkType.NAME, "expected compiler type directive", "expected: @compiler_known_type(\"name\")")
        if directive.repr != "compiler_known_type":
            try errorFatal(p, "COMPILER_TYPE", "unsupported type compiler directive", "currently supported: @compiler_known_type", directive.pos)
        ..
        p.consume()
        opening := try p.peek()
        try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected '(' after compiler type directive", "expected: @compiler_known_type(\"name\")")
        p.consume()
        value := try p.peek()
        try ensureTkType(p, value, tkt.TkType.LIT_STR, "expected compiler-known type name", "expected a string literal")
        p.consume()
        closing := try p.peek()
        try ensureKwType(p, closing, tkt.KwType.PAREN_CL, "expected ')' after compiler-known type name", "expected: )")
        p.consume()
        current = try makeType(p, nt.Type.CompilerKnown(name=value.repr))
    elif start.kwType == tkt.KwType.FN:
        p.consume()
        opening := try p.peek()
        try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected '(' after fn", "expected: fn(Type, ...) ReturnType")
        p.consume()
        args := nt.emptyNodeArray[nt.Type*]()
        try consumeNewLines(p)
        next := try p.peek()
        if next.kwType != tkt.KwType.PAREN_CL:
            loop true:
                argType := try parseType(p)
                try args.pushRight(ctx.alloc, argType)
                delimiter := try p.peek()
                if delimiter.kwType == tkt.KwType.PAREN_CL:
                    break
                ..
                try ensureKwType(p, delimiter, tkt.KwType.COMMA, "expected ',' or ')' in function type", "expected: fn(Type, ...) ReturnType")
                p.consume()
                try consumeNewLines(p)
                next = try p.peek()
                if next.kwType == tkt.KwType.PAREN_CL:
                    break
                ..
            ..
        ..
        closing := try p.peek()
        try ensureKwType(p, closing, tkt.KwType.PAREN_CL, "expected ')' after function type arguments", "expected: )")
        p.consume()
        retType := try parseType(p)
        current = try makeType(p, nt.Type.Function(args=move args, returnType=retType, noContext=noContext))
    else:
        if noContext:
            try errorFatal(p, "NOCTX_TYPE", "noctx must modify a function type", "expected: noctx fn(Types) ReturnType", start.pos)
        ..
        name := try parseName(p, true)
        current = try makeType(p, nt.Type.Named(name=name, id=0))
    ..

    loop true:
        if p.idx >= p.file.tokens.count():
            break
        ..
        t := try p.peek()
        if t.kwType == tkt.KwType.ASTERIX:
            p.consume()
            current = try makeType(p, nt.Type.Pointer(toType=current))
        elif t.kwType == tkt.KwType.BRACK_OP:
            if p.idx + 1 >= p.file.tokens.count():
                break
            ..
            inner := try p.file.tokens.get(p.idx + 1)
            if inner.type != tkt.TkType.NAME && inner.kwType != tkt.KwType.BRACK_CL:
                break
            ..
            p.consume()
            inner = try p.peek()
            if inner.kwType == tkt.KwType.BRACK_CL:
                p.consume()
                current = try makeType(p, nt.Type.Slice(ofType=current))
            else:
                args := nt.emptyNodeArray[nt.Type*]()
                loop true:
                    arg := try parseType(p)
                    try args.pushRight(ctx.alloc, arg)
                    delimiter := try p.peek()
                    if delimiter.kwType == tkt.KwType.BRACK_CL:
                        break
                    ..
                    if delimiter.kwType == tkt.KwType.COMMA || delimiter.kwType == tkt.KwType.NEWLINE:
                        p.consume()
                        following := try p.peek()
                        loop following.kwType == tkt.KwType.NEWLINE:
                            p.consume()
                            following = try p.peek()
                        ..
                        if following.kwType == tkt.KwType.BRACK_CL:
                            break
                        ..
                        continue
                    ..
                    try nonFatalError(p, "TYPE_ARGS", "expected a type argument delimiter", "expected: comma or ]", delimiter.pos)
                    try skipToListBoundary(p, tkt.KwType.BRACK_CL)
                    break
                ..
                close := try p.peek()
                try ensureKwType(p, close, tkt.KwType.BRACK_CL, "expected closing bracket after type arguments", "expected: ]")
                p.consume()
                current = try makeType(p, nt.Type.Templated(owner=current, args=move args))
            ..
        else:
            break
        ..
    ..
    if owned:
        current = try makeType(p, nt.Type.Owned(ofType=current))
    ..
    if throwing:
        current = try makeType(p, nt.Type.Throwing(ofType=current))
    ..
    ret current
..

parseTypedArgListAfterOpen(p Parser*) !$nt.NodeArray[nt.Expr*]:
    try consumeNewLines(p)

    fields := nt.emptyNodeArray[nt.Expr*]()
    t := try p.peek()
    if t.kwType == tkt.KwType.PAREN_CL:
        p.consume()
        ret move fields
    ..
    loop true:
        field := try parseVarDefTyped(p)
        try fields.pushRight(ctx.alloc, field)
        try consumeListSeparators(p, tkt.KwType.PAREN_CL)
        delimiter := try p.peek()
        if delimiter.kwType == tkt.KwType.PAREN_CL:
            break
        ..
    ..
    closing := try p.peek()
    try ensureKwType(p, closing, tkt.KwType.PAREN_CL, "expected closing parenthesis after function type arguments", "expected: )")
    p.consume()
    ret move fields
..

consumeNewLines(p Parser*) !void:
    loop true:
        t := try p.peek()
        if t.kwType == tkt.KwType.NEWLINE:
            p.consume()
        else:
            ret
        ..
    ..
..

skipToListBoundary(p Parser*, end tkt.KwType) !void:
    loop p.idx < p.file.tokens.count():
        t := try p.peek()
        if t.kwType == end:
            ret
        elif t.kwType == tkt.KwType.COMMA || t.kwType == tkt.KwType.NEWLINE:
            p.consume()
            ret
        ..
        p.consume()
    ..
..

skipToLineEnd(p Parser*) !void:
    loop p.idx < p.file.tokens.count():
        t := try p.peek()
        p.consume()
        if t.kwType == tkt.KwType.NEWLINE:
            ret
        ..
    ..
..

consumeListSeparators(p Parser*, end tkt.KwType) !void:
    foundComma := false
    atLeastOneSeparator := false

    loop true:
        t := try p.peek()
        if t.type != tkt.TkType.KEYWORD:
            if atLeastOneSeparator:
                ret
            ..

            try nonFatalError(p, "LIST_DELIMITER", "unexpected token while expected list element delimiter", "expected: comma, newline, or closing delimiter", t.pos)
            try skipToListBoundary(p, end)
            ret
        ..

        if t.kwType == tkt.KwType.COMMA && not foundComma:
            foundComma = true
            atLeastOneSeparator = true
            p.consume()
        elif t.kwType == tkt.KwType.NEWLINE:
            atLeastOneSeparator = true
            p.consume()
        elif t.kwType == tkt.KwType.COMMA && foundComma:
            try nonFatalError(p, "LIST_DELIMITER", "consecutive commas in list are forbidden", "remove the extra comma", t.pos)
            p.consume()
        elif t.kwType == end:
            ret
        else:
            if atLeastOneSeparator:
                ret
            ..

            try nonFatalError(p, "LIST_DELIMITER", "unexpected token while expected list element delimiter", "expected: comma, newline, or closing delimiter", t.pos)
            try skipToListBoundary(p, end)
            ret
        ..
    ..
..

makeExpr(p Parser*, value nt.Expr) !nt.Expr*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.Expr]()
..

makeType(p Parser*, value nt.Type) !nt.Type*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.Type]()
..

newImplementedTypes() $nt.NodeArray[nt.Type*]:
    ret nt.emptyNodeArray[nt.Type*]()
..

makeStmt(p Parser*, value nt.Stmt) !nt.Stmt*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.Stmt]()
..

makeGlStmt(p Parser*, value nt.GlobalStmt) !nt.GlobalStmt*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.GlobalStmt]()
..

makeName(p Parser*, value nt.Name) !nt.Name*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.Name]()
..

makeLiteral(p Parser*, value nt.Literal) !nt.Literal*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.Literal]()
..

makeHeader(p Parser*, value nt.Header) !nt.Header*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.Header]()
..

makeMatchCase(p Parser*, value nt.MatchCase) !nt.MatchCase*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.MatchCase]()
..

makeProtoMethod(p Parser*, value nt.ProtoMethod) !nt.ProtoMethod*:
    id := try p.file.astNodes.push(value.proto[nt.Node]())
    node := try p.file.astNodes.get(id)
    ret try node.implBorrow[nt.ProtoMethod]()
..

binaryPrecedence(t tkt.Token) u8:
    if t.type != tkt.TkType.KEYWORD:
        ret 0
    ..
    if t.kwType == tkt.KwType.ASTERIX || t.kwType == tkt.KwType.SLASH || t.kwType == tkt.KwType.PERCENT:
        ret 70
    elif t.kwType == tkt.KwType.EQUAL || t.kwType == tkt.KwType.INFER:
        ret 5
    elif t.kwType == tkt.KwType.PLUS || t.kwType == tkt.KwType.MINUS:
        ret 60
    elif t.kwType == tkt.KwType.SHIFT_L || t.kwType == tkt.KwType.SHIFT_R:
        ret 55
    elif t.kwType == tkt.KwType.CMP_EQ || t.kwType == tkt.KwType.CMP_NEQ || t.kwType == tkt.KwType.CMP_LT || t.kwType == tkt.KwType.CMP_GT || t.kwType == tkt.KwType.CMP_LTEQ || t.kwType == tkt.KwType.CMP_GTEQ:
        ret 50
    elif t.kwType == tkt.KwType.AMPERSAND:
        ret 45
    elif t.kwType == tkt.KwType.CARET:
        ret 40
    elif t.kwType == tkt.KwType.PIPE:
        ret 35
    elif t.kwType == tkt.KwType.ANDAND:
        ret 30
    elif t.kwType == tkt.KwType.OROR:
        ret 20
    ..
    ret 0
..

parseExpression(p Parser*, minPrec u8) !nt.Expr*:
    left := try parseExprPrefix(p)

    loop true:
        if p.idx >= p.file.tokens.count():
            ret left
        ..
        op := try p.peek()
        # A comma or newline ends the current expression. Keep this explicit
        # so list delimiters cannot be consumed as part of Pratt parsing.
        if op.kwType == tkt.KwType.COMMA || op.kwType == tkt.KwType.NEWLINE || op.kwType == tkt.KwType.COLON:
            ret left
        ..
        # Postfix member selection binds more tightly than every infix
        # operator and is applied to the complete expression on its left.
        if op.kwType == tkt.KwType.DOT:
            if 90 < minPrec:
                ret left
            ..
            p.consume()
            memberTk := try p.peek()
            if memberTk.type != tkt.TkType.NAME:
                try errorFatal(p, "UNEXPECTED_TOK", "expected member name after '.'", "expected: <name>", memberTk.pos)
            ..
            p.consume()
            member := try makeExpr(p, nt.Expr.Named(type=none, name=memberTk.repr, declId=0))
            left = try makeExpr(p, nt.Expr.MemberAccess(type=none, owner=left, member=member))
            continue
        ..
        # Calls are postfix operations too. The callee may be a name or a
        # member-access expression; either way it is already a stable node.
        if op.kwType == tkt.KwType.PAREN_OP:
            if 90 < minPrec:
                ret left
            ..
            args := try parseCallArgs(p)
            # every calls are parsed as indirect calls for now
            # later steps will reveal if a call is direct or indirect
            # this will be very useful when it comes to LLVM lowering
            # here the distinction between direct/indirect is whether
            # what we call is a global name (classical function)
            # or a pointer to a function
            left = try makeExpr(p, nt.Expr.IndirectCall(
                type=none, owner=left, args=move args,
            ))
            continue
        ..
        if op.kwType == tkt.KwType.BRACK_OP:
            if 90 < minPrec:
                ret left
            ..
            genericCall := false
            genericReference := false
            hasTopLevelTypeComma := false
            depth u64 = 0
            for i := p.idx to p.file.tokens.count():
                candidate := try p.file.tokens.get(i)
                if candidate.kwType == tkt.KwType.BRACK_OP:
                    depth = depth + 1
                elif candidate.kwType == tkt.KwType.BRACK_CL:
                    depth = depth - 1
                    if depth == 0:
                        if i + 1 < p.file.tokens.count():
                            following := try p.file.tokens.get(i + 1)
                            genericCall = following.kwType == tkt.KwType.PAREN_OP
                            genericReference = not genericCall && hasTopLevelTypeComma && (following.kwType == tkt.KwType.COMMA || following.kwType == tkt.KwType.PAREN_CL)
                        ..
                        break
                    ..
                elif candidate.kwType == tkt.KwType.COMMA && depth == 1:
                    hasTopLevelTypeComma = true
                ..
            ..
            if genericCall:
                typeArgs := try parseTemplateArgs(p)
                args := try parseCallArgs(p)
                left = try makeExpr(p, nt.Expr.TemplatedIndirectCall(type=none, owner=left, args=move args, typeArgs=move typeArgs))
                continue
            ..
            if genericReference:
                typeArgs := try parseTemplateArgs(p)
                left = try makeExpr(p, nt.Expr.GenericApply(owner=left, typeArgs=move typeArgs))
                continue
            ..
            p.consume()
            index := try parseExpression(p, 0)
            close := try p.peek()
            try ensureKwType(p, close, tkt.KwType.BRACK_CL, "expected closing bracket after subscript", "expected: ]")
            p.consume()
            left = try makeExpr(p, nt.Expr.Subscript(type=none, owner=left, index=index))
            continue
        ..
        prec := binaryPrecedence(op)
        if prec == 0 || prec < minPrec:
            ret left
        ..

        p.consume()
        rightMin := prec + 1
        if op.kwType == tkt.KwType.EQUAL || op.kwType == tkt.KwType.INFER:
            rightMin = prec
        ..
        right := try parseExpression(p, rightMin)
        if op.kwType == tkt.KwType.EQUAL || op.kwType == tkt.KwType.INFER:
            left = try makeExpr(p, nt.Expr.Assign(type=none, assignee=left, expr=right))
        else:
            left = try makeExpr(p, nt.Expr.Binary(type=none, op=cast.u64to8(op.kwType), left=left, right=right))
        ..
    ..
..

parseCallArgs(p Parser*) !$nt.NodeArray[nt.Expr*]:
    opening := try p.peek()
    try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected opening parenthesis for call", "expected: (")
    p.consume()

    try consumeNewLines(p)

    values := nt.emptyNodeArray[nt.Expr*]()
    t := try p.peek()
    if t.kwType != tkt.KwType.PAREN_CL:
        loop true:
            # Keep the argument loop synchronized even when a previous
            # expression stopped directly on a separator.
            loop true:
                t = try p.peek()
                if t.kwType == tkt.KwType.COMMA || t.kwType == tkt.KwType.NEWLINE:
                    p.consume()
                else:
                    break
                ..
            ..
            t = try p.peek()
            if t.kwType == tkt.KwType.PAREN_CL:
                break
            ..
            value := try parseExpression(p, 0)
            try values.pushRight(ctx.alloc, value)

            t = try p.peek()
            if t.kwType == tkt.KwType.PAREN_CL:
                break
            ..
            if t.kwType == tkt.KwType.COMMA || t.kwType == tkt.KwType.NEWLINE:
                p.consume()
                loop t.kwType == tkt.KwType.NEWLINE:
                    t = try p.peek()
                    if t.kwType == tkt.KwType.NEWLINE:
                        p.consume()
                    else:
                        break
                    ..
                ..
                t = try p.peek()
                if t.kwType == tkt.KwType.PAREN_CL:
                    break
                ..
                continue
            ..
            try nonFatalError(p, "CALL_DELIMITER", "expected call argument delimiter", "expected: , or )", t.pos)
            try skipToListBoundary(p, tkt.KwType.PAREN_CL)
            afterRecovery := try p.peek()
            if afterRecovery.kwType == tkt.KwType.PAREN_CL:
                break
            ..
        ..
    ..

    closing := try p.peek()
    try ensureKwType(p, closing, tkt.KwType.PAREN_CL, "expected closing parenthesis after call arguments", "expected: )")
    p.consume()

    ret move values
..

parseLiteral(p Parser*) !nt.Expr*:
    t := try p.peek()
    p.consume()

    lit nt.Literal = nt.Literal.Number(value=t.repr)
    if t.type == tkt.TkType.LIT_STR:
        lit = nt.Literal.String(value=t.repr)
    elif t.type == tkt.TkType.LIT_BOOL:
        lit = nt.Literal.Boolean(value=t.repr == "true")
    elif t.type == tkt.TkType.LIT_NONE:
        lit = nt.Literal.None()
    elif t.type == tkt.TkType.LIT_CHAR8:
        lit = nt.Literal.Char8(value=t.repr)
    elif t.type == tkt.TkType.LIT_CHAR32:
        lit = nt.Literal.Char32(value=t.repr)
    ..
    litPtr := try makeLiteral(p, lit)
    ret try makeExpr(p, nt.Expr.Literal(type=none, literal=litPtr))
..

parseExprPrefix(p Parser*) !nt.Expr*:
    t := try p.peek()

    if t.kwType == tkt.KwType.TRUE || t.kwType == tkt.KwType.FALSE || t.kwType == tkt.KwType.NONE_LIT:
        p.consume()
        literal nt.Literal
        if t.kwType == tkt.KwType.TRUE:
            literal = nt.Literal.Boolean(value=true)
        elif t.kwType == tkt.KwType.FALSE:
            literal = nt.Literal.Boolean(value=false)
        else:
            literal = nt.Literal.None()
        ..
        literalPtr := try makeLiteral(p, literal)
        ret try makeExpr(p, nt.Expr.Literal(type=none, literal=literalPtr))
    ..

    if t.kwType == tkt.KwType.AT:
        p.consume()
        directive := try p.peek()
        if directive.type != tkt.TkType.NAME && directive.kwType != tkt.KwType.LLVM:
            try errorFatal(p, "UNEXPECTED_TOK", "expected compiler directive after '@'", "expected: @llvm(...) or @embed(\"path\")", directive.pos)
        ..

        if directive.repr == "llvm":
            p.consume()
            opening := try p.peek()
            try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected '(' after @llvm", "expected: @llvm(\"operation\", ...)")
            p.consume()
            operation := try p.peek()
            try ensureTkType(p, operation, tkt.TkType.LIT_STR, "expected @llvm operation name", "expected a string literal")
            p.consume()
            depth u64 = 1
            loop depth > 0:
                item := try p.peek()
                if item.kwType == tkt.KwType.PAREN_OP:
                    depth = depth + 1
                elif item.kwType == tkt.KwType.PAREN_CL:
                    depth = depth - 1
                ..
                p.consume()
            ..
            ret try makeExpr(p, nt.Expr.InlineLLVM(operation=operation.repr))
        ..

        # this is shit from a butt, this needs to be in a list, not hardcoded
        isEmbed := directive.repr == "embed"
        isKnownConst := directive.repr == "compiler_known"
        if not isEmbed && not isKnownConst:
            try errorFatal(p, "COMPILER_DIRECTIVE", "unsupported expression compiler directive", "currently supported: @embed and @compiler_known", directive.pos)
        ..
        p.consume()
        opening := try p.peek()
        try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected '(' after compiler directive", "expected: @embed(\"path\")")
        p.consume()
        source := try p.peek()
        try ensureTkType(p, source, tkt.TkType.LIT_STR, "expected string argument to compiler directive", "expected a string literal")
        p.consume()
        closing := try p.peek()
        try ensureKwType(p, closing, tkt.KwType.PAREN_CL, "expected ')' after compiler directive argument", "expected: )")
        p.consume()
        if isKnownConst:
            ret try makeExpr(p, nt.Expr.CompilerKnown(name=source.repr))
        ..
        fromDir := try path.parent(p.file.path)
        defer fromDir.free()
        parts := [2]str(fromDir, source.repr)
        absolute := try path.join(parts)
        ret try makeExpr(p, nt.Expr.Embed(path=move absolute))
    ..

    if t.kwType == tkt.KwType.BRACK_OP:
        p.consume()
        length nt.Expr* = none
        inferLength := false
        closing := try p.peek()
        if closing.kwType == tkt.KwType.BRACK_CL:
            inferLength = true
        else:
            length = try parseExpression(p, 0)
            closing = try p.peek()
            try ensureKwType(p, closing, tkt.KwType.BRACK_CL, "expected closing bracket after array length", "expected: [length] Type or []Type(...)")
        ..
        p.consume()
        elementType := try parseType(p)
        if inferLength:
            initializer := try p.peek()
            try ensureKwType(p, initializer, tkt.KwType.PAREN_OP, "inferred array length requires an initializer list", "expected: []Type(...)")
        ..
        ret try makeExpr(p, nt.Expr.Array(type=elementType, length=length, inferLength=inferLength))
    ..

    if t.kwType == tkt.KwType.TRY:
        p.consume()
        call := try parseExpression(p, 80)
        ret try makeExpr(p, nt.Expr.Try(type=none, call=call))
    ..

    if t.type == tkt.TkType.NAME && t.repr == "move":
        p.consume()
        operand := try parseExpression(p, 80)
        ret try makeExpr(p, nt.Expr.Move(operand=operand))
    ..

    if t.type == tkt.TkType.NAME:
        p.consume()
        ret try makeExpr(p, nt.Expr.Named(type=none, name=t.repr, declId=0))
    ..

    if t.type >= tkt.TkType.LIT_STR && t.type <= tkt.TkType.LIT_CHAR32:
        ret try parseLiteral(p)
    ..

    if t.type == tkt.TkType.KEYWORD && t.kwType == tkt.KwType.SIZEOF:
        p.consume()
        operandType := try parseType(p)
        ret try makeExpr(p, nt.Expr.Sizeof(type=none, operand=operandType))
    ..

    if t.type == tkt.TkType.KEYWORD && (t.kwType == tkt.KwType.MINUS || t.kwType == tkt.KwType.NOT || t.kwType == tkt.KwType.TILDE || t.kwType == tkt.KwType.ASTERIX || t.kwType == tkt.KwType.AMPERSAND || t.kwType == tkt.KwType.ADDROF):
        p.consume()
        operand := try parseExpression(p, 80)
        ret try makeExpr(p, nt.Expr.Unary(type=none, op=cast.u64to8(t.kwType), operand=operand))
    ..

    if t.kwType == tkt.KwType.PAREN_OP:
        p.consume()
        inner := try parseExpression(p, 0)
        close := try p.peek()
        try ensureKwType(p, close, tkt.KwType.PAREN_CL, "expected closing parenthesis", "expected: )")
        p.consume()
        ret inner
    ..

    try errorFatal(p, "UNEXPECTED_EXPR", "unexpected token while parsing expression", "expected a literal, name, unary expression, or parenthesized expression", t.pos)
    ret none
..

# Only used for single names or composite names
# Not to be used in expressions
parseName(p Parser*, allowComposite bool) !nt.Name*:
    t := try p.peek()
    try ensureTkType(p, t, tkt.TkType.NAME, "unexpected token while expected name", "expected: <name>, <name>.<method>")
    p.consume()

    if not allowComposite:
        ret try makeName(p, nt.Name.Simple(name=t.repr))
    ..

    if p.idx >= p.file.tokens.count():
        ret try makeName(p, nt.Name.Simple(name=t.repr))
    ..
    followingPart := try p.peek()
    if followingPart.kwType != tkt.KwType.DOT:
        ret try makeName(p, nt.Name.Simple(name=t.repr))
    ..

    # Keep the common simple-name path allocation-free.
    names := nt.emptyNodeArray[str]()
    try names.pushRight(ctx.alloc, t.repr)

    loop true:
        if p.idx >= p.file.tokens.count():
            break
        ..
        next := try p.peek()
        if next.kwType != tkt.KwType.DOT:
            break
        ..
        p.consume()
        part := try p.peek()
        try ensureTkType(p, part, tkt.TkType.NAME, "expected name after '.'", "expected: <name>.<name>")
        try names.pushRight(ctx.alloc, part.repr)
        p.consume()
    ..

    ret try makeName(p, nt.Name.Composite(names=move names))
..

parseNameSimple(p Parser*) !str:
    t := try p.peek()
    try ensureTkType(p, t, tkt.TkType.NAME, "unexpected token while expected name", "expected: <name>")
    p.consume()
    ret t.repr
..

# used for speculative parsing with already parsed name
parseVarDefTypedWithName(p Parser*, name str) !nt.Expr*:
    type := try parseType(p)
    boundedCount str = ""
    next := try p.peek()
    if next.kwType == tkt.KwType.BOUNDED:
        p.consume()
        extent := try p.peek()
        if extent.type != tkt.TkType.NAME && extent.type != tkt.TkType.LIT_NUM:
            try errorFatal(p, "BOUNDED_EXTENT", "bounded parameter extent must be a name or non-negative integer", "expected: pointer Type bounded count", extent.pos)
        ..
        boundedCount = extent.repr
        p.consume()
    ..
    ret try makeExpr(p, nt.Expr.VarDef(type=type, name=name, declId=0, boundedCount=boundedCount))
..

parseVarDefTyped(p Parser*) !nt.Expr*:
    name := try parseNameSimple(p)
    ret try parseVarDefTypedWithName(p, name)
..

parseTypedArgList(p Parser*) !$nt.NodeArray[nt.Expr*]:
    t := try p.peek()
    # ensure (
    try ensureKwType(p, t, tkt.KwType.PAREN_OP, "unexpected token while expected opening parenthesis", "expected: (")
    p.consume()

    try consumeNewLines(p)

    fields := nt.emptyNodeArray[nt.Expr*]()

    t = try p.peek()
    if t.kwType == tkt.KwType.PAREN_CL:
        p.consume()
        ret move fields
    ..

    loop true:
        field := try parseVarDefTyped(p)
        try fields.pushRight(ctx.alloc, field)
        try consumeListSeparators(p, tkt.KwType.PAREN_CL)
        delimiter := try p.peek()
        if delimiter.kwType == tkt.KwType.PAREN_CL:
            break
        ..
    ..
    t = try p.peek()
    try ensureKwType(p, t, tkt.KwType.PAREN_CL, "unexpected token while expected closing parenthesis", "expected: )")
    p.consume()

    ret move fields
..

parseTemplateArgs(p Parser*) !$nt.NodeArray[nt.Type*]:
    t := try p.peek()
    # ensure (
    try ensureKwType(p, t, tkt.KwType.BRACK_OP, "unexpected token while expected opening bracket", "expected: [")
    p.consume()

    types := nt.emptyNodeArray[nt.Type*]()

    loop true:
        type := try parseType(p)
        try types.pushRight(ctx.alloc, type)
        try consumeListSeparators(p, tkt.KwType.BRACK_CL)
        delimiter := try p.peek()
        if delimiter.kwType == tkt.KwType.BRACK_CL:
            break
        ..
    ..
    t = try p.peek()
    try ensureKwType(p, t, tkt.KwType.BRACK_CL, "unexpected token while expected closing bracket", "expected: ]")
    p.consume()

    ret move types
..

parseHeader(p Parser*, name str) !nt.Header*:
    t := try p.peek()
    try ensureTkType(p, t, tkt.TkType.KEYWORD, "unexpected token while expected opening parenthesis or bracket", "expected: <name>(arg Type, ...), <name>[Type](arg Type, ...)")

    kind := nt.HeaderKind.Plain()
    if t.kwType == tkt.KwType.BRACK_OP:
        kind = nt.HeaderKind.Templated(typeArgs=try parseTemplateArgs(p))
    ..

    fields := try parseTypedArgList(p)
    ret try makeHeader(p, nt.Header(id=0, scopeId=0, name=name, fields=move fields, kind=move kind))
..

headerIsTemplated(header nt.Header*) bool:
    kind := header.kind
    match kind as value:
    case nt.HeaderKind.Plain:
        ret false
    case nt.HeaderKind.Templated:
        ret true
    ..
    ret false
..

parseStatement(p Parser*) !nt.Stmt*:
    t := try p.peek()
    if t.type == tkt.TkType.NAME && p.idx + 1 < p.file.tokens.count():
        following := try p.file.tokens.get(p.idx + 1)
        if following.kwType == tkt.KwType.COMMA:
            ret try parseDestructureStatement(p)
        ..
        if following.type == tkt.TkType.NAME || following.kwType == tkt.KwType.INFER || following.kwType == tkt.KwType.DOLLAR || following.kwType == tkt.KwType.EXCLAM || following.kwType == tkt.KwType.NOCTX:
            ret try parseVariableStatement(p)
        ..
    ..
    if t.kwType == tkt.KwType.NEWLINE:
        p.consume()
        ret try makeStmt(p, nt.Stmt.Expression(expr=try makeExpr(p, nt.Expr.Empty())))
    elif t.kwType == tkt.KwType.RETURN:
        p.consume()
        expr := try makeExpr(p, nt.Expr.Empty())
        if p.idx < p.file.tokens.count():
            next := try p.peek()
            if next.kwType != tkt.KwType.NEWLINE && next.kwType != tkt.KwType.DOTS:
                value := try parseExpression(p, 0)
                expr = try makeExpr(p, nt.Expr.Return(expr=value))
            else:
                expr = try makeExpr(p, nt.Expr.Return(expr=none))
            ..
        else:
            expr = try makeExpr(p, nt.Expr.Return(expr=none))
        ..
        ret try makeStmt(p, nt.Stmt.Expression(expr=expr))
    elif t.kwType == tkt.KwType.THROW:
        p.consume()
        value := try parseExpression(p, 0)
        ret try makeStmt(p, nt.Stmt.Expression(expr=try makeExpr(p, nt.Expr.Throw(expr=value))))
    elif t.kwType == tkt.KwType.BREAK:
        p.consume()
        ret try makeStmt(p, nt.Stmt.Break())
    elif t.kwType == tkt.KwType.CONTINUE:
        p.consume()
        ret try makeStmt(p, nt.Stmt.Continue())
    elif t.kwType == tkt.KwType.DEFER || t.kwType == tkt.KwType.ONERROR || t.kwType == tkt.KwType.UNSAFE:
        p.consume()
        next := try p.peek()
        expr nt.Expr* = none
        body nt.Stmt* = none
        if next.kwType == tkt.KwType.COLON:
            body = try parseBody(p)
        else:
            expr = try parseExpression(p, 0)
        ..
        if t.kwType == tkt.KwType.DEFER:
            ret try makeStmt(p, nt.Stmt.Defer(expr=expr, body=body))
        elif t.kwType == tkt.KwType.ONERROR:
            ret try makeStmt(p, nt.Stmt.OnError(expr=expr, body=body))
        ..
        ret try makeStmt(p, nt.Stmt.Unsafe(expr=expr, body=body))
    elif t.kwType == tkt.KwType.BOUNDED:
        p.consume()
        predicates := nt.emptyNodeArray[nt.Expr*]()
        pointers := nt.emptyNodeArray[nt.Expr*]()
        extents := nt.emptyNodeArray[nt.Expr*]()
        loop true:
            first := try p.peek()
            hasBy := false
            if first.type == tkt.TkType.NAME && p.idx + 1 < p.file.tokens.count():
                second := try p.file.tokens.get(p.idx + 1)
                hasBy = second.type == tkt.TkType.NAME && second.repr == "by"
            ..
            if hasBy:
                pointer := try parseExpression(p, 90)
                by := try p.peek()
                try ensureTkType(p, by, tkt.TkType.NAME, "expected 'by' after bounded pointer", "expected: bounded pointer by extent")
                if by.repr != "by":
                    try errorFatal(p, "BOUNDED_BY", "expected 'by' after bounded pointer", "", by.pos)
                ..
                p.consume()
                extent := try parseExpression(p, 0)
                try pointers.pushRight(ctx.alloc, pointer)
                try extents.pushRight(ctx.alloc, extent)
            else:
                predicate := try parseExpression(p, 0)
                try predicates.pushRight(ctx.alloc, predicate)
            ..
            delimiter := try p.peek()
            if delimiter.kwType == tkt.KwType.COLON:
                break
            ..
            try ensureKwType(p, delimiter, tkt.KwType.COMMA, "expected comma between bounded predicates", "expected: , or :")
            p.consume()
        ..
        if predicates.count() == 0 && pointers.count() == 0:
            try errorFatal(p, "EMPTY_BOUNDED", "bounded requires a comparison or pointer extent", "", t.pos)
        ..
        body := try parseBody(p)
        ret try makeStmt(p, nt.Stmt.Bounded(predicates=move predicates, pointers=move pointers, extents=move extents, body=body))
    elif t.kwType == tkt.KwType.MATCH:
        ret try parseMatchStmt(p)
    elif t.kwType == tkt.KwType.LLVM:
        p.consume()
        if p.idx >= p.file.tokens.count():
            try nonFatalError(p, "LLVM_TEXT", "expected LLVM text string", "expected: llvm \"<LLVM text>\"", t.pos)
            ret try makeStmt(p, nt.Stmt.Expression(expr=try makeExpr(p, nt.Expr.Empty())))
        ..
        textTk := try p.peek()
        textErr := ensureTkType(p, textTk, tkt.TkType.LIT_STR, "expected LLVM text string", "expected: llvm \"<LLVM text>\"")
        if textErr.nok():
            try nonFatalError(p, "LLVM_TEXT", "expected LLVM text string", "expected: llvm \"<LLVM text>\"", textTk.pos)
            try skipToLineEnd(p)
            ret try makeStmt(p, nt.Stmt.Expression(expr=try makeExpr(p, nt.Expr.Empty())))
        ..
        p.consume()
        if p.idx < p.file.tokens.count():
            end := try p.peek()
            endErr := ensureKwType(p, end, tkt.KwType.NEWLINE, "expected end of line after LLVM text", "expected: newline")
            if endErr.nok():
                try nonFatalError(p, "LLVM_TRAILING_TOKENS", "unexpected tokens after LLVM text", "LLVM statements must end at the newline", end.pos)
                try skipToLineEnd(p)
            else:
                p.consume()
            ..
        ..
        ret try makeStmt(p, nt.Stmt.LLVM(text=textTk.repr))
    elif t.kwType == tkt.KwType.IF:
        ret try parseIfStmt(p)
    elif t.kwType == tkt.KwType.LOOP:
        p.consume()
        condition := try parseExpression(p, 0)
        body := try parseBody(p)
        ret try makeStmt(p, nt.Stmt.Loop(condition=condition, body=body))
    elif t.kwType == tkt.KwType.FOR:
        ret try parseForStmt(p)
    else:
        expr := try parseExpression(p, 0)
        ret try makeStmt(p, nt.Stmt.Expression(expr=expr))
    ..
..

parseDestructureStatement(p Parser*) !nt.Stmt*:
    valueName := try parseNameSimple(p)
    comma := try p.peek()
    try ensureKwType(p, comma, tkt.KwType.COMMA, "expected comma in destructuring declaration", "expected: value, error := call()")
    p.consume()
    errorName := try parseNameSimple(p)
    infer := try p.peek()
    try ensureKwType(p, infer, tkt.KwType.INFER, "destructuring declarations require inferred assignment", "expected: :=")
    p.consume()
    call := try parseExpression(p, 0)
    valueId := try registerLocalDecl(p, valueName, none, comma.pos)
    errorId := try registerLocalDecl(p, errorName, none, comma.pos)
    expr := try makeExpr(p, nt.Expr.VarDefAssignDestructure(type=none, nameValue=valueName, nameError=errorName, call=call, valueDeclId=valueId, errorDeclId=errorId))
    ret try makeStmt(p, nt.Stmt.Expression(expr=expr))
..

parseMatchArmBody(p Parser*) !nt.Stmt*:
    opening := try p.peek()
    try ensureKwType(p, opening, tkt.KwType.COLON, "expected ':' after match arm", "expected: case Union.Variant:")
    p.consume()
    oldScope := p.scope
    scopeId u64 = 0
    if p.scope != none:
        p.scope = try p.scope.registerScope(decl.ScopeKind.Block())
        scopeId = p.scope.id
    ..
    statements := nt.emptyNodeArray[nt.Stmt*]()
    loop true:
        t := try p.peek()
        if t.kwType == tkt.KwType.NEWLINE:
            p.consume()
            continue
        elif t.kwType == tkt.KwType.CASE || t.kwType == tkt.KwType.ELSE || t.kwType == tkt.KwType.DOTS:
            p.scope = oldScope
            ret try makeStmt(p, nt.Stmt.Body(statements=move statements, scopeId=scopeId))
        ..
        statement := try parseStatement(p)
        try statements.pushRight(ctx.alloc, statement)
    ..
..

parseMatchStmt(p Parser*) !nt.Stmt*:
    p.consume()
    expression := try parseExpression(p, 0)
    asTk := try p.peek()
    try ensureKwType(p, asTk, tkt.KwType.AS, "match requires a narrowed binding", "expected: match value as binding:")
    p.consume()
    binding := try parseNameSimple(p)
    oldScope := p.scope
    if p.scope != none:
        p.scope = try p.scope.registerScope(decl.ScopeKind.Block())
    ..
    bindingDeclId := try registerLocalDecl(p, binding, none, asTk.pos)
    opening := try p.peek()
    try ensureKwType(p, opening, tkt.KwType.COLON, "expected ':' after match binding", "expected: match value as binding:")
    p.consume()

    cases := nt.emptyNodeArray[nt.MatchCase*]()
    elseBody nt.Stmt* = none
    loop true:
        t := try p.peek()
        if t.kwType == tkt.KwType.NEWLINE:
            p.consume()
            continue
        elif t.kwType == tkt.KwType.DOTS:
            p.consume()
            p.scope = oldScope
            break
        elif t.kwType == tkt.KwType.ELSE:
            p.consume()
            elseBody = try parseMatchArmBody(p)
        elif t.kwType == tkt.KwType.CASE:
            p.consume()
            variant := try parseName(p, true)
            localVariant nt.Name
            unsafe localVariant = *variant
            match localVariant as variantName:
            case nt.Name.Composite:
                if variantName.names.count() < 2:
                    try nonFatalError(p, "MATCH_VARIANT", "match case must name a union variant", "expected: case Union.Variant:", t.pos)
                ..
            case nt.Name.Simple:
                try nonFatalError(p, "MATCH_VARIANT", "match case must name a union variant", "expected: case Union.Variant:", t.pos)
            ..
            body := try parseMatchArmBody(p)
            node := try makeMatchCase(p, nt.MatchCase(variant=variant, body=body))
            try cases.pushRight(ctx.alloc, node)
        else:
            try nonFatalError(p, "MATCH_ARM", "expected case, else, or end of match", "expected: case, else, or ...", t.pos)
            loop p.idx < p.file.tokens.count():
                next := try p.peek()
                if next.kwType == tkt.KwType.CASE || next.kwType == tkt.KwType.ELSE || next.kwType == tkt.KwType.DOTS:
                    break
                ..
                p.consume()
            ..
        ..
    ..
    ret try makeStmt(p, nt.Stmt.Match(expression=expression, binding=binding, bindingDeclId=bindingDeclId, cases=move cases, elseBody=elseBody))
..

parseVariableStatement(p Parser*) !nt.Stmt*:
    nameTk := try p.peek()
    name := try parseNameSimple(p)
    next := try p.peek()
    type nt.Type* = none
    if next.kwType != tkt.KwType.INFER:
        type = try parseType(p)
        if p.idx < p.file.tokens.count():
            next = try p.peek()
        else:
            next.kwType = tkt.KwType.NONE
        ..
        if next.kwType == tkt.KwType.COMMA:
            p.consume()
            errorNameTk := try p.peek()
            errorName := try parseNameSimple(p)
            errorType := try parseType(p)
            assign := try p.peek()
            try ensureKwType(p, assign, tkt.KwType.EQUAL, "expected '=' after destructured declaration types", "expected: value Type, errorName ErrorType = call()")
            p.consume()
            call := try parseExpression(p, 0)
            valueDeclId := try registerLocalDecl(p, name, type, nameTk.pos)
            errorDeclId := try registerLocalDecl(p, errorName, errorType, errorNameTk.pos)
            expr := try makeExpr(p, nt.Expr.VarDefAssignDestructure(type=type, nameValue=name, nameError=errorName, call=call, valueDeclId=valueDeclId, errorDeclId=errorDeclId))
            ret try makeStmt(p, nt.Stmt.Expression(expr=expr))
        ..
    ..

    if next.kwType == tkt.KwType.EQUAL || next.kwType == tkt.KwType.INFER:
        p.consume()
        value := try parseExpression(p, 0)
        declId := try registerLocalDecl(p, name, type, nameTk.pos)
        expr := try makeExpr(p, nt.Expr.VarDefAssign(type=type, name=name, assignment=value, declId=declId))
        ret try makeStmt(p, nt.Stmt.Expression(expr=expr))
    ..
    declId := try registerLocalDecl(p, name, type, nameTk.pos)
    expr := try makeExpr(p, nt.Expr.VarDef(type=type, name=name, declId=declId, boundedCount=""))
    ret try makeStmt(p, nt.Stmt.Expression(expr=expr))
..

parseIfStmt(p Parser*) !nt.Stmt*:
    t := try p.peek()
    p.consume()
    condition := try parseExpression(p, 0)
    body := try parseBody(p)

    nextStmt nt.Stmt* = none
    if p.idx < p.file.tokens.count():
        next := try p.peek()
        if next.kwType == tkt.KwType.ELIF || next.kwType == tkt.KwType.ELSE:
            nextStmt = try parseIfTail(p)
        ..
    ..
    ret try makeStmt(p, nt.Stmt.If(condition=condition, body=body, next=nextStmt))
..

parseIfTail(p Parser*) !nt.Stmt*:
    t := try p.peek()
    if t.kwType == tkt.KwType.ELIF:
        p.consume()
        condition := try parseExpression(p, 0)
        body := try parseBody(p)
        next := try p.peek()
        tail nt.Stmt* = none
        if next.kwType == tkt.KwType.ELIF || next.kwType == tkt.KwType.ELSE:
            tail = try parseIfTail(p)
        ..
        ret try makeStmt(p, nt.Stmt.Elif(condition=condition, body=body, next=tail))
    elif t.kwType == tkt.KwType.ELSE:
        p.consume()
        body := try parseBody(p)
        ret try makeStmt(p, nt.Stmt.Else(body=body))
    ..
    ret none
..

parseForStmt(p Parser*) !nt.Stmt*:
    p.consume()
    nameTk := try p.peek()
    name := try parseNameSimple(p)
    oldScope := p.scope
    loopScopeId u64 = 0
    if p.scope != none:
        p.scope = try p.scope.registerScope(decl.ScopeKind.Block())
        loopScopeId = p.scope.id
    ..
    next := try p.peek()
    index nt.Expr*
    varType nt.Type* = none
    initial nt.Expr*
    if next.kwType == tkt.KwType.INFER:
        p.consume()
        initial = try parseExpression(p, 0)
    else:
        varType = try parseType(p)
        assign := try p.peek()
        try ensureKwType(p, assign, tkt.KwType.EQUAL, "expected initial value for for-loop index", "expected: = <expression>")
        p.consume()
        initial = try parseExpression(p, 0)
    ..
    declId := try registerLocalDecl(p, name, varType, nameTk.pos)
    index = try makeExpr(p, nt.Expr.VarDefAssign(type=varType, name=name, assignment=initial, declId=declId))
    toToken := try p.peek()
    try ensureKwType(p, toToken, tkt.KwType.TO, "expected 'to' after for-loop index", "expected: to <bound>")
    p.consume()
    bound := try parseExpression(p, 0)
    body := try parseBody(p)
    p.scope = oldScope
    ret try makeStmt(p, nt.Stmt.ForLoop(index=index, bound=bound, body=body, scopeId=loopScopeId))
..

parseBody(p Parser*) !nt.Stmt*:
    t := try p.peek()
    try ensureKwType(p, t, tkt.KwType.COLON, "unexpected token while expected block opening", "expected: ':'")
    p.consume()

    oldScope := p.scope
    bodyScopeId u64 = 0
    if p.scope != none:
        p.scope = try p.scope.registerScope(decl.ScopeKind.Block())
        bodyScopeId = p.scope.id
    ..

    statements := nt.emptyNodeArray[nt.Stmt*]()

    loop true:
        if p.idx < p.file.tokens.count():
            t = try p.peek()
        else:
            t.kwType = tkt.KwType.NONE
        ..
        if t.kwType == tkt.KwType.DOTS:
            p.consume()
            p.scope = oldScope
            ret try makeStmt(p, nt.Stmt.Body(statements=move statements, scopeId=bodyScopeId))
        elif t.kwType == tkt.KwType.ELIF || t.kwType == tkt.KwType.ELSE:
            p.scope = oldScope
            ret try makeStmt(p, nt.Stmt.Body(statements=move statements, scopeId=bodyScopeId))
        elif t.kwType == tkt.KwType.NEWLINE:
            p.consume()
            continue
        ..

        stmt := try parseStatement(p)
        try statements.pushRight(ctx.alloc, stmt)
    ..
..

Parser.parsePrunedGlobal() !void:
    originalModule := this.module
    scratchModule := try decl.registerModule(this.file.path)
    this.module = scratchModule
    _ := try parseGlobalStmt(this)
    this.module = originalModule
..

parseGlobalStmt(p Parser*) !nt.GlobalStmt*:
    t := try p.peek()

    if t.kwType == tkt.KwType.AT:
        p.consume()
        directive := try p.peek()
        try ensureTkType(p, directive, tkt.TkType.NAME, "expected compiler directive name", "expected: @platform(\"linux\")")
        if directive.repr != "platform":
            try errorFatal(p, "COMPILER_DIRECTIVE", "unsupported module directive", "currently supported: @platform", directive.pos)
        ..
        p.consume()
        opening := try p.peek()
        try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected '(' after platform directive", "expected: @platform(\"platform\", ...)")
        p.consume()
        matched := false
        loop true:
            value := try p.peek()
            try ensureTkType(p, value, tkt.TkType.LIT_STR, "expected platform name", "expected a string literal")
            # The current compiler targets its host. The host OS is inferred
            # from the current-directory convention; target selection will
            # replace this once it is exposed by the driver.
            matchesWindows := value.repr == "windows" && strgs.byteAt(gl.cwd, 1) == 58
            matchesUnix := value.repr == "linux" && strgs.byteAt(gl.cwd, 0) == 47
            matchesDefaultArch := value.repr == "x86_64"
            if matchesWindows || matchesUnix || matchesDefaultArch:
                matched = true
            ..
            p.consume()
            delimiter := try p.peek()
            if delimiter.kwType == tkt.KwType.PAREN_CL:
                p.consume()
                break
            ..
            try ensureKwType(p, delimiter, tkt.KwType.COMMA, "expected ',' or ')' in platform directive", "expected: @platform(\"linux\", ...)")
            p.consume()
        ..
        if p.idx < p.file.tokens.count():
            end := try p.peek()
            if end.kwType == tkt.KwType.NEWLINE:
                p.consume()
            ..
        ..
        p.pruneNext = not matched
        ret none
    ..

    if t.type == tkt.TkType.NAME && t.repr == "proto":
        ret try parseProtoDecl(p)
    ..

    if t.type == tkt.TkType.NAME: # could be either header or module-scoped vardef
        isPublic := p.pendingPublic
        isGlobal := p.pendingGlobal
        isConst := p.pendingConst
        noContext := p.pendingNoCtx
        isDestructor := p.pendingDestructor
        p.pendingPublic = false
        p.pendingGlobal = false
        p.pendingConst = false
        p.pendingNoCtx = false
        p.pendingDestructor = false
        namePos := t.pos
        genericOwnerType nt.Type* = none
        name nt.Name*
        genericOwnerMethod := false
        if p.idx + 1 < p.file.tokens.count():
            possibleOpen := try p.file.tokens.get(p.idx + 1)
            if possibleOpen.kwType == tkt.KwType.BRACK_OP:
                depth u64 = 0
                afterArgs u64 = p.idx + 1
                for i := p.idx + 1 to p.file.tokens.count():
                    candidate := try p.file.tokens.get(i)
                    if candidate.kwType == tkt.KwType.BRACK_OP:
                        depth = depth + 1
                    elif candidate.kwType == tkt.KwType.BRACK_CL:
                        depth = depth - 1
                        if depth == 0:
                            afterArgs = i + 1
                            break
                        ..
                    ..
                ..
                if afterArgs < p.file.tokens.count():
                    afterOwner := try p.file.tokens.get(afterArgs)
                    genericOwnerMethod = afterOwner.kwType == tkt.KwType.DOT
                ..
            ..
        ..
        if genericOwnerMethod:
            ownerTk := try p.peek()
            p.consume()
            ownerArgs := try parseTemplateArgs(p)
            dot := try p.peek()
            p.consume()
            memberTk := try p.peek()
            try ensureTkType(p, memberTk, tkt.TkType.NAME, "expected method name after generic owner", "expected: Type[T].method(args)")
            p.consume()
            names := nt.emptyNodeArray[str]()
            try names.pushRight(ctx.alloc, ownerTk.repr)
            try names.pushRight(ctx.alloc, memberTk.repr)
            name = try makeName(p, nt.Name.Composite(names=move names))
            ownerName := try makeName(p, nt.Name.Simple(name=ownerTk.repr))
            ownerType := try makeType(p, nt.Type.Named(name=ownerName, id=0))
            genericOwnerType = try makeType(p, nt.Type.Templated(owner=ownerType, args=move ownerArgs))
        else:
            name = try parseName(p, true)
        ..
        localName nt.Name
        unsafe localName = *name # workaround since match doesn't work yet with pointer types

        if p.idx < p.file.tokens.count():
            t = try p.peek()
        else:
            t.kwType = tkt.KwType.NONE
        ..

        match localName as n:
        case nt.Name.Composite:
            if isGlobal || isConst:
                try errorFatal(p, "METHOD_MODIFIER", "global and const cannot modify a method", "", namePos)
            ..
            if n.names.count() != 2:
                try errorFatal(p, "METHOD_NAME", "method declarations require Owner.method", "expected: Type.method(args) ReturnType:", namePos)
            ..
            ownerName := try n.names.get(0)
            methodName := try n.names.get(1)
            ownerNode := try makeName(p, nt.Name.Simple(name=ownerName))
            ownerType nt.Type* = genericOwnerType
            if ownerType == none:
                ownerType = try makeType(p, nt.Type.Named(name=ownerNode, id=0))
            ..
            if t.kwType != tkt.KwType.PAREN_OP && t.kwType != tkt.KwType.BRACK_OP:
                try errorFatal(p, "METHOD_HEADER", "expected method argument list", "expected: Owner.method(args)", t.pos)
            ..
            header := try parseHeader(p, methodName)
            oldScope := p.scope
            try registerHeaderArgs(p, header, decl.ScopeKind.Method())
            methodScope := try p.module.getScope(header.scopeId)
            receiverNameIdx, receiverNameErr := methodScope.names.indexOf("this")
            if receiverNameErr.ok():
                try nonFatalError(p, "DUPLICATE_ARGUMENT", "method arguments cannot shadow the receiver name 'this'", "rename the method argument", namePos)
            else:
                try methodScope.registerDecl("this", decl.DeclKind.Argument(name="this", type=ownerType, boundedCount=""))
            ..
            retType := try parseType(p)
            body := try parseBody(p)
            p.scope = oldScope
            qualifiedName := try strgs.concat(ownerName, ".")
            defer qualifiedName.free()
            fullName := try strgs.concat(qualifiedName, methodName)
            defer fullName.free()
            registered := try registerParsedDecl(p, fullName, decl.DeclKind.Function(name=fullName, returnType=retType), namePos)
            header.id = registered.id
            method := try makeGlStmt(p, nt.GlobalStmt.Function(header=header, retType=retType, body=body, isPublic=isPublic, noContext=noContext, isDestructor=isDestructor))
            methodNode := try makeName(p, nt.Name.Simple(name=methodName))
            ret try makeGlStmt(p, nt.GlobalStmt.Method(ownerType=ownerType, name=methodNode, methodBody=method))
        case nt.Name.Simple:
            nameStr := n.name

            # A concrete implementation declaration defines the type named
            # here and records its implemented prototypes on that declaration.
            if t.type == tkt.TkType.NAME && t.repr == "impl":
                if isGlobal || isConst || noContext || isDestructor:
                    try errorFatal(p, "STRUCT_MODIFIER", "invalid modifier on implementation declaration", "implementation declarations define a type", namePos)
                ..
                p.consume()
                implements := newImplementedTypes()
                t = try p.peek()
                loop t.kwType != tkt.KwType.PAREN_OP:
                    implementedType := try parseType(p)
                    try implements.pushRight(ctx.alloc, implementedType)
                    t = try p.peek()
                ..
                header := try parseHeader(p, nameStr)
                end := try p.peek()
                try ensureKwType(p, end, tkt.KwType.NEWLINE, "expected end of line after implementation declaration", "expected: newline")
                registered := try registerParsedDecl(p, nameStr, decl.DeclKind.Struct(name=nameStr), namePos)
                header.id = registered.id
                try registerHeaderFields(p, header)
                p.pendingPublic = false
                ret try makeGlStmt(p, nt.GlobalStmt.Struct(header=header, implements=move implements, isPublic=isPublic))
            ..

            if t.kwType == tkt.KwType.PAREN_OP || t.kwType == tkt.KwType.BRACK_OP:
                if isGlobal || isConst || isDestructor:
                    try errorFatal(p, "FUNCTION_MODIFIER", "global, const, and destr cannot modify a function or struct", "destr applies to methods", namePos)
                ..
                header := try parseHeader(p, nameStr)

                if p.idx < p.file.tokens.count():
                    t = try p.peek()
                else:
                    t.kwType = tkt.KwType.NEWLINE
                ..
                if t.kwType != tkt.KwType.NEWLINE:

                    # no newline after header => function
                    # ex: name(args T) T2 <- you are here
                    oldScope := p.scope
                    try registerHeaderArgs(p, header, decl.ScopeKind.Function())
                    retType := try parseType(p)
                    body := try parseBody(p)
                    p.scope = oldScope
                    registered := try registerParsedDecl(p, nameStr, decl.DeclKind.Function(name=nameStr, returnType=retType), namePos)
                    header.id = registered.id
                    ret try makeGlStmt(p, nt.GlobalStmt.Function(header=header, retType=retType, body=body, isPublic=isPublic, noContext=noContext, isDestructor=false))
                else:
                    if noContext:
                        try errorFatal(p, "STRUCT_MODIFIER", "noctx cannot modify a struct", "", namePos)
                    ..
                    # a struct is just a header without body
                    registered := try registerParsedDecl(p, nameStr, decl.DeclKind.Struct(name=nameStr), namePos)
                    header.id = registered.id
                    try registerHeaderFields(p, header)
                    ret try makeGlStmt(p, nt.GlobalStmt.Struct(header=header, implements=newImplementedTypes(), isPublic=isPublic))
                ..
            else:
                if noContext || isDestructor:
                    try errorFatal(p, "VARIABLE_MODIFIER", "noctx and destr cannot modify a variable", "", namePos)
                ..
                varType nt.Type* = none
                initializer nt.Expr* = none
                if t.kwType == tkt.KwType.INFER:
                    p.consume()
                    initializer = try parseExpression(p, 0)
                else:
                    varType = try parseType(p)
                    if p.idx < p.file.tokens.count():
                        t = try p.peek()
                    else:
                        t.kwType = tkt.KwType.NONE
                    ..
                    if t.kwType == tkt.KwType.EQUAL:
                        p.consume()
                        initializer = try parseExpression(p, 0)
                    ..
                ..
                if isConst && initializer == none:
                    try errorFatal(p, "CONST_INITIALIZER", "constant declaration requires an initializer", "expected: const name Type = value", namePos)
                ..
                if isGlobal && isConst:
                    try errorFatal(p, "GLOBAL_CONST", "global cannot modify a constant", "global storage applies to mutable variables", namePos)
                ..
                registered := try registerParsedDecl(p, nameStr, decl.DeclKind.Variable(name=nameStr, type=varType), namePos)
                ret try makeGlStmt(p, nt.GlobalStmt.Variable(id=registered.id, name=nameStr, type=varType, initializer=initializer, isPublic=isPublic, isGlobal=isGlobal, isConst=isConst))
            ..
        ..

        try errorFatal(p, "INVALID_DECLARATION", "could not parse declaration after name", "expected a function, struct, or variable declaration", namePos)
    elif t.type == tkt.TkType.KEYWORD:
        if t.kwType == tkt.KwType.NEWLINE:
            p.consume()
            ret none
        ..
        if t.kwType == tkt.KwType.USE:
            isPublic := p.pendingPublic
            p.pendingPublic = false
            try parseUseDecl(p, isPublic, p.pruneNext)
            ret none
        ..
        if t.kwType == tkt.KwType.MODULE:
            moduleTk := t
            if p.moduleSeen:
                try nonFatalError(p, "DUPLICATE_MODULE", "duplicate module declaration", "only one module declaration is allowed", t.pos)
            ..
            if p.pendingPublic || p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
                try nonFatalError(p, "MODULE_MODIFIER", "modifiers cannot be applied to module declarations", "", t.pos)
                p.pendingPublic = false
                p.pendingGlobal = false
                p.pendingConst = false
                p.pendingNoCtx = false
                p.pendingDestructor = false
            ..
            p.consume()
            p.moduleSeen = true
            if p.idx >= p.file.tokens.count():
                try nonFatalError(p, "MODULE_NAME", "expected module name", "expected: mod <name>", moduleTk.pos)
                ret none
            ..
            name := try p.peek()
            isKeywordModuleName := name.kwType == tkt.KwType.LLVM && name.repr == p.file.modName
            if not isKeywordModuleName:
                nameErr := ensureTkType(p, name, tkt.TkType.NAME, "expected module name", "expected: mod <name>")
                if nameErr.nok():
                    try nonFatalError(p, "MODULE_NAME", "expected module name", "expected: mod <name>", name.pos)
                    try skipToLineEnd(p)
                    ret none
                ..
            ..
            if name.repr != p.file.modName:
                try nonFatalError(p, "MODULE_NAME", "module declaration does not match the file module name", "", moduleTk.pos)
            ..
            p.consume()
            if p.idx < p.file.tokens.count():
                newline := try p.peek()
                endErr := ensureKwType(p, newline, tkt.KwType.NEWLINE, "expected end of line after module declaration", "expected: newline")
                if endErr.nok():
                    try nonFatalError(p, "MODULE_TRAILING_TOKENS", "unexpected tokens after module declaration", "module declarations must end at the newline", newline.pos)
                    try skipToLineEnd(p)
                    ret none
                ..
                p.consume()
            ..
            ret none
        ..
        if t.kwType == tkt.KwType.LINK:
            p.consume()
            if p.idx >= p.file.tokens.count():
                try nonFatalError(p, "LINK_LIBRARY", "expected library name after link", "expected: link \"<library>\"", t.pos)
                ret none
            ..
            library := try p.peek()
            libraryErr := ensureTkType(p, library, tkt.TkType.LIT_STR, "expected library name after link", "expected: link \"<library>\"")
            if libraryErr.nok():
                try nonFatalError(p, "LINK_LIBRARY", "expected library name after link", "expected: link \"<library>\"", library.pos)
                try skipToLineEnd(p)
                p.pendingPublic = false
                p.pendingGlobal = false
                p.pendingConst = false
                p.pendingNoCtx = false
                p.pendingDestructor = false
                ret none
            ..
            if library.repr == "":
                try nonFatalError(p, "LINK_LIBRARY", "native library name cannot be empty", "", library.pos)
            ..
            p.consume()
            if p.pendingPublic || p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
                try nonFatalError(p, "LINK_MODIFIER", "modifiers cannot be applied to link directives", "", t.pos)
                p.pendingPublic = false
                p.pendingGlobal = false
                p.pendingConst = false
                p.pendingNoCtx = false
                p.pendingDestructor = false
            ..
            if p.idx < p.file.tokens.count():
                newline := try p.peek()
                endErr := ensureKwType(p, newline, tkt.KwType.NEWLINE, "expected end of line after link directive", "expected: newline")
                if endErr.nok():
                    try nonFatalError(p, "LINK_TRAILING_TOKENS", "unexpected tokens after link directive", "link directives must end at the newline", newline.pos)
                    try skipToLineEnd(p)
                    ret none
                ..
                p.consume()
            ..
            if library.repr != "":
                try p.file.nativeLibs.pushRight(strgs.copy(library.repr))
            ..
            ret none
        ..
        if t.kwType == tkt.KwType.BUNDLE:
            p.consume()
            if p.idx >= p.file.tokens.count():
                try nonFatalError(p, "BUNDLE_PATH", "expected file path after bundle", "expected: bundle \"<file>\"", t.pos)
                ret none
            ..
            bun := try p.peek()
            bundleErr := ensureTkType(p, bun, tkt.TkType.LIT_STR, "expected file path after bundle", "expected: bundle \"<file>\"")
            if bundleErr.nok():
                try nonFatalError(p, "BUNDLE_PATH", "expected file path after bundle", "expected: bundle \"<file>\"", bun.pos)
                try skipToLineEnd(p)
                p.pendingPublic = false
                p.pendingGlobal = false
                p.pendingConst = false
                p.pendingNoCtx = false
                p.pendingDestructor = false
                ret none
            ..
            if p.pendingPublic || p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
                try nonFatalError(p, "BUNDLE_MODIFIER", "modifiers cannot be applied to bundle directives", "", t.pos)
                p.pendingPublic = false
                p.pendingGlobal = false
                p.pendingConst = false
                p.pendingNoCtx = false
                p.pendingDestructor = false
            ..
            p.consume()
            if p.idx < p.file.tokens.count():
                newline := try p.peek()
                endErr := ensureKwType(p, newline, tkt.KwType.NEWLINE, "expected end of line after bundle directive", "expected: newline")
                if endErr.nok():
                    try nonFatalError(p, "BUNDLE_TRAILING_TOKENS", "unexpected tokens after bundle directive", "bundle directives must end at the newline", newline.pos)
                    try skipToLineEnd(p)
                    ret none
                ..
                p.consume()
            ..
            fromDir := try path.parent(p.file.path)
            defer fromDir.free()
            bundleParts := [2]str(fromDir, bun.repr)
            absBundle := try path.join(bundleParts)
            try p.file.bundles.pushRight(move absBundle)
            ret none
        ..
        if t.kwType == tkt.KwType.PUBLIC:
            p.consume()
            next := try p.peek()
            if next.kwType == tkt.KwType.USE:
                if p.pendingPublic:
                    try nonFatalError(p, "DUPLICATE_MODIFIER", "duplicate pub modifier", "a use directive can only be modified by pub once", t.pos)
                ..
                try parseUseDecl(p, true, p.pruneNext)
                ret none
            ..
            if p.pendingPublic:
                try nonFatalError(p, "DUPLICATE_MODIFIER", "duplicate pub modifier", "a declaration can only be modified by pub once", t.pos)
            ..
            p.pendingPublic = true
            ret try parseGlobalStmt(p)
        elif t.kwType == tkt.KwType.GLOBAL:
            p.consume()
            if p.pendingGlobal:
                try nonFatalError(p, "DUPLICATE_MODIFIER", "duplicate global modifier", "a declaration can only be modified by global once", t.pos)
            ..
            p.pendingGlobal = true
            ret try parseGlobalStmt(p)
        elif t.kwType == tkt.KwType.CONST:
            p.consume()
            if p.pendingConst:
                try nonFatalError(p, "DUPLICATE_MODIFIER", "duplicate const modifier", "a declaration can only be modified by const once", t.pos)
            ..
            p.pendingConst = true
            ret try parseGlobalStmt(p)
        elif t.kwType == tkt.KwType.NOCTX:
            p.consume()
            if p.pendingNoCtx:
                try nonFatalError(p, "DUPLICATE_MODIFIER", "duplicate noctx modifier", "a declaration can only be modified by noctx once", t.pos)
            ..
            p.pendingNoCtx = true
            ret try parseGlobalStmt(p)
        elif t.kwType == tkt.KwType.DESTR:
            p.consume()
            if p.pendingDestructor:
                try nonFatalError(p, "DUPLICATE_MODIFIER", "duplicate destr modifier", "a declaration can only be modified by destr once", t.pos)
            ..
            p.pendingDestructor = true
            ret try parseGlobalStmt(p)
        elif t.kwType == tkt.KwType.ALIAS:
            if p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
                try errorFatal(p, "ALIAS_MODIFIER", "global, const, noctx, and destr cannot modify an alias", "", t.pos)
            ..
            p.consume()
            aliasName := try parseNameSimple(p)
            eq := try p.peek()
            try ensureKwType(p, eq, tkt.KwType.EQUAL, "expected '=' in alias declaration", "expected: alias Name = Type")
            p.consume()
            aliasType := try parseType(p)
            isPublic := p.pendingPublic
            p.pendingPublic = false
            registered := try registerParsedDecl(p, aliasName, decl.DeclKind.Alias(name=aliasName, target=aliasType), t.pos)
            ret try makeGlStmt(p, nt.GlobalStmt.Alias(id=registered.id, name=try makeName(p, nt.Name.Simple(name=aliasName)), type=aliasType, isPublic=isPublic))
        elif t.kwType == tkt.KwType.UNION:
            if p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
                try errorFatal(p, "UNION_MODIFIER", "global and const cannot modify a union", "", t.pos)
            ..
            ret try parseUnionDecl(p)
        elif t.kwType == tkt.KwType.ENUM:
            if p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
                try errorFatal(p, "ENUM_MODIFIER", "global and const cannot modify an enum", "", t.pos)
            ..
            ret try parseEnumDecl(p)
        elif t.kwType == tkt.KwType.EXTERN:
            if p.pendingGlobal || p.pendingConst || p.pendingDestructor:
                try errorFatal(p, "EXTERN_MODIFIER", "global, const, and destr cannot modify an external function", "", t.pos)
            ..
            p.consume()
            nameTk := try p.peek()
            try ensureTkType(p, nameTk, tkt.TkType.NAME, "expected external function name", "expected: ext name(args) ReturnType")
            p.consume()
            externalTk := try p.peek()
            try ensureTkType(p, externalTk, tkt.TkType.NAME, "expected external symbol name", "expected: ext name symbol(args) ReturnType")
            p.consume()
            header := try parseHeader(p, nameTk.repr)
            oldScope := p.scope
            try registerHeaderArgs(p, header, decl.ScopeKind.Function())
            retType := try parseType(p)
            p.scope = oldScope
            registered := try registerParsedDecl(p, nameTk.repr, decl.DeclKind.Function(name=nameTk.repr, returnType=retType), nameTk.pos)
            header.id = registered.id
            isPublic := p.pendingPublic
            p.pendingPublic = false
            isNoCtx := p.pendingNoCtx
            p.pendingNoCtx = false
            ret try makeGlStmt(p, nt.GlobalStmt.ExternalFunction(header=header, externalName=externalTk.repr, retType=retType, isPublic=isPublic, noContext=isNoCtx))
        elif t.kwType == tkt.KwType.LLVM:
            if p.pendingPublic || p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
                try errorFatal(p, "LLVM_MODIFIER", "modifiers cannot be applied to inline LLVM declarations", "", t.pos)
            ..
            p.consume()
            if p.idx >= p.file.tokens.count():
                try nonFatalError(p, "LLVM_TEXT", "expected LLVM text string", "expected: llvm \"<LLVM text>\"", t.pos)
                ret none
            ..
            textTk := try p.peek()
            textErr := ensureTkType(p, textTk, tkt.TkType.LIT_STR, "expected LLVM text string", "expected: llvm \"<LLVM text>\"")
            if textErr.nok():
                try nonFatalError(p, "LLVM_TEXT", "expected LLVM text string", "expected: llvm \"<LLVM text>\"", textTk.pos)
                try skipToLineEnd(p)
                ret none
            ..
            p.consume()
            if p.idx < p.file.tokens.count():
                end := try p.peek()
                endErr := ensureKwType(p, end, tkt.KwType.NEWLINE, "expected end of line after LLVM text", "expected: newline")
                if endErr.nok():
                    try nonFatalError(p, "LLVM_TRAILING_TOKENS", "unexpected tokens after LLVM text", "LLVM declarations must end at the newline", end.pos)
                    try skipToLineEnd(p)
                    ret none
                ..
                p.consume()
            ..
            ret try makeGlStmt(p, nt.GlobalStmt.LLVM(text=textTk.repr))
        ..
        try nonFatalError(p, "INVALID_DECLARATION", "unsupported declaration keyword", "expected a supported module-level declaration", t.pos)
        try skipToLineEnd(p)
    else:
        try nonFatalError(p, "UNEXPECTED_TOK_GL", "unexpected token in module's scope", "expected: declaration, directive, or newline", p.currPos())
        try skipToLineEnd(p)
    ..
    ret none
..

parseProtoDecl(p Parser*) !nt.GlobalStmt*:
    protoTk := try p.peek()
    if p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
        try errorFatal(p, "PROTO_MODIFIER", "global, const, noctx, and destr cannot modify a prototype", "", protoTk.pos)
    ..
    p.consume()
    nameTk := try p.peek()
    try ensureTkType(p, nameTk, tkt.TkType.NAME, "expected prototype name", "expected: proto Name(method(args) ReturnType)")
    p.consume()
    isPublic := p.pendingPublic
    p.pendingPublic = false
    registered := try registerParsedDecl(p, nameTk.repr, decl.DeclKind.Proto(name=nameTk.repr), nameTk.pos)
    protoScope := try p.module.registerScope(decl.ScopeKind.Block())
    opening := try p.peek()
    implements := nt.emptyNodeArray[nt.Type*]()
    if opening.type == tkt.TkType.NAME && opening.repr == "impl":
        p.consume()
        opening = try p.peek()
        loop opening.kwType != tkt.KwType.PAREN_OP:
            implementedType := try parseType(p)
            try implements.pushRight(ctx.alloc, implementedType)
            opening = try p.peek()
        ..
    ..
    try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected prototype method list", "expected: (")
    p.consume()

    methods := nt.emptyNodeArray[nt.ProtoMethod*]()
    loop true:
        t := try p.peek()
        if t.kwType == tkt.KwType.PAREN_CL:
            p.consume()
            break
        elif t.kwType == tkt.KwType.COMMA || t.kwType == tkt.KwType.NEWLINE:
            p.consume()
            continue
        ..
        noContext := false
        if t.kwType == tkt.KwType.NOCTX:
            noContext = true
            p.consume()
            t = try p.peek()
        ..
        if t.type != tkt.TkType.NAME:
            try nonFatalError(p, "PROTO_METHOD_NAME", "expected prototype method name", "expected: method(args) ReturnType", t.pos)
            try skipToListBoundary(p, tkt.KwType.PAREN_CL)
            continue
        ..
        try ensureTkType(p, t, tkt.TkType.NAME, "expected prototype method name", "expected: method(args) ReturnType")
        p.consume()
        header := try parseHeader(p, t.repr)
        if headerIsTemplated(header):
            try nonFatalError(p, "PROTO_GENERIC_METHOD", "prototype requirements cannot be generic", "declare a generic ordinary method on the prototype instead", t.pos)
        ..
        oldScope := p.scope
        try registerHeaderArgs(p, header, decl.ScopeKind.Method())
        protoReceiverNameIdx, receiverNameErr := p.scope.names.indexOf("this")
        if receiverNameErr.ok():
            try nonFatalError(p, "DUPLICATE_ARGUMENT", "prototype arguments cannot shadow 'this'", "rename the prototype argument", t.pos)
        else:
            protoName := try makeName(p, nt.Name.Simple(name=nameTk.repr))
            protoType := try makeType(p, nt.Type.Named(name=protoName, id=registered.id))
            try p.scope.registerDecl("this", decl.DeclKind.Argument(name="this", type=protoType, boundedCount=""))
        ..
        returnType := try parseType(p)
        p.scope = oldScope

        methodNameIdx, methodNameErr := protoScope.names.indexOf(t.repr)
        duplicateMethod := methodNameErr.ok()
        if duplicateMethod:
            try nonFatalError(p, "DUPLICATE_PROTO_METHOD", "prototype method name is repeated", "method names must be unique", t.pos)
        ..
        if not headerIsTemplated(header) && not duplicateMethod:
            qualifiedName := try strgs.concat(nameTk.repr, ".")
            defer qualifiedName.free()
            fullName := try strgs.concat(qualifiedName, t.repr)
            methodDecl := try protoScope.registerDecl(t.repr, decl.DeclKind.Function(name=move fullName, returnType=returnType))
            header.id = methodDecl.id
            method := try makeProtoMethod(p, nt.ProtoMethod(id=methodDecl.id, header=header, returnType=returnType, noContext=noContext))
            try methods.pushRight(ctx.alloc, method)
        ..

        delimiter := try p.peek()
        if delimiter.kwType == tkt.KwType.COMMA || delimiter.kwType == tkt.KwType.NEWLINE:
            p.consume()
        elif delimiter.kwType != tkt.KwType.PAREN_CL:
            try nonFatalError(p, "PROTO_DELIMITER", "expected delimiter between prototype methods", "expected: comma, newline, or )", delimiter.pos)
            try skipToListBoundary(p, tkt.KwType.PAREN_CL)
        ..
    ..
    ret try makeGlStmt(p, nt.GlobalStmt.Proto(id=registered.id, name=nameTk.repr, scopeId=protoScope.id, implements=move implements, methods=move methods, isPublic=isPublic))
..

parseUnionDecl(p Parser*) !nt.GlobalStmt*:
    _ := try p.peek()
    p.consume()
    nameTk := try p.peek()
    try ensureTkType(p, nameTk, tkt.TkType.NAME, "expected union name", "expected: union Name(...)")
    p.consume()
    registered := try registerParsedDecl(p, nameTk.repr, decl.DeclKind.Union(name=nameTk.repr), nameTk.pos)
    scope := try p.module.registerScope(decl.ScopeKind.Block())
    opening := try p.peek()
    implements := nt.emptyNodeArray[nt.Type*]()
    if opening.type == tkt.TkType.NAME && opening.repr == "impl":
        p.consume()
        opening = try p.peek()
        loop opening.kwType != tkt.KwType.PAREN_OP:
            implementedType := try parseType(p)
            try implements.pushRight(ctx.alloc, implementedType)
            opening = try p.peek()
        ..
    ..
    try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected union variant list", "expected: (")
    p.consume()

    variants := nt.emptyNodeArray[nt.Header*]()
    loop true:
        t := try p.peek()
        if t.kwType == tkt.KwType.PAREN_CL:
            p.consume()
            break
        elif t.kwType == tkt.KwType.NEWLINE || t.kwType == tkt.KwType.COMMA:
            p.consume()
            continue
        ..
        if t.type != tkt.TkType.NAME:
            try nonFatalError(p, "UNION_VARIANT_NAME", "expected union variant name", "expected: Variant or Variant(fields)", t.pos)
            try skipToListBoundary(p, tkt.KwType.PAREN_CL)
            continue
        ..
        try ensureTkType(p, t, tkt.TkType.NAME, "expected union variant name", "expected: Variant or Variant(fields)")
        p.consume()
        next := try p.peek()
        header nt.Header*
        if next.kwType == tkt.KwType.PAREN_OP:
            fields := try parseTypedArgList(p)
            header = try makeHeader(p, nt.Header(id=0, scopeId=0, name=t.repr, fields=move fields, kind=nt.HeaderKind.Plain()))
        else:
            emptyFields := nt.emptyNodeArray[nt.Expr*]()
            header = try makeHeader(p, nt.Header(id=0, scopeId=0, name=t.repr, fields=move emptyFields, kind=nt.HeaderKind.Plain()))
        ..
        unionVariantNameIdx, variantNameErr := scope.names.indexOf(t.repr)
        duplicateVariant := variantNameErr.ok()
        if duplicateVariant:
            try nonFatalError(p, "DUPLICATE_UNION_VARIANT", "union variant name is repeated", "variant names must be unique", t.pos)
        else:
            try registerHeaderFields(p, header)
            variantDecl := try scope.registerDecl(t.repr, decl.DeclKind.UnionVariant(name=t.repr))
            header.id = variantDecl.id
            try variants.pushRight(ctx.alloc, header)
        ..
        delimiter := try p.peek()
        if delimiter.kwType == tkt.KwType.COMMA || delimiter.kwType == tkt.KwType.NEWLINE:
            p.consume()
        elif delimiter.kwType != tkt.KwType.PAREN_CL:
            try nonFatalError(p, "UNION_DELIMITER", "expected delimiter between union variants", "expected: comma, newline, or )", delimiter.pos)
            try skipToListBoundary(p, tkt.KwType.PAREN_CL)
        ..
    ..
    if variants.count() == 0:
        try nonFatalError(p, "EMPTY_UNION", "union must declare at least one variant", "", nameTk.pos)
    ..
    isPublic := p.pendingPublic
    p.pendingPublic = false
    ret try makeGlStmt(p, nt.GlobalStmt.Union(id=registered.id, name=nameTk.repr, scopeId=scope.id, implements=move implements, variants=move variants, isPublic=isPublic))
..

parseEnumDecl(p Parser*) !nt.GlobalStmt*:
    _ := try p.peek()
    p.consume()
    nameTk := try p.peek()
    try ensureTkType(p, nameTk, tkt.TkType.NAME, "expected enum name", "expected: enum Name Type(...)")
    p.consume()
    backing := try parseType(p)
    opening := try p.peek()
    try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected enum value list", "expected: (")
    registered := try registerParsedDecl(p, nameTk.repr, decl.DeclKind.Enum(name=nameTk.repr, backing=backing), nameTk.pos)
    scope := try p.module.registerScope(decl.ScopeKind.Block())
    p.consume()

    variants := nt.emptyNodeArray[nt.Expr*]()
    loop true:
        t := try p.peek()
        if t.kwType == tkt.KwType.PAREN_CL:
            p.consume()
            break
        elif t.kwType == tkt.KwType.NEWLINE || t.kwType == tkt.KwType.COMMA:
            p.consume()
            continue
        ..
        if t.type != tkt.TkType.NAME:
            try nonFatalError(p, "ENUM_VARIANT_NAME", "expected enum variant name", "expected: <name> [= value]", t.pos)
            try skipToListBoundary(p, tkt.KwType.PAREN_CL)
            continue
        ..
        try ensureTkType(p, t, tkt.TkType.NAME, "expected enum variant name", "expected: <name> [= value]")
        p.consume()
        enumVariantNameIdx, variantNameErr := scope.names.indexOf(t.repr)
        duplicateVariant := variantNameErr.ok()
        if duplicateVariant:
            try nonFatalError(p, "DUPLICATE_ENUM_VARIANT", "enum value name is repeated", "enum value names must be unique", t.pos)
        else:
            variantDecl := try scope.registerDecl(t.repr, decl.DeclKind.EnumVariant(name=t.repr, type=backing))
            value nt.Expr*
            assign := try p.peek()
            if assign.kwType == tkt.KwType.EQUAL:
                p.consume()
                explicitValue := try parseExpression(p, 0)
                value = try makeExpr(p, nt.Expr.VarDefAssign(type=none, name=t.repr, assignment=explicitValue, declId=variantDecl.id))
            else:
                value = try makeExpr(p, nt.Expr.VarDef(type=none, name=t.repr, declId=variantDecl.id, boundedCount=""))
            ..
            try variants.pushRight(ctx.alloc, value)
        ..
        delimiter := try p.peek()
        if delimiter.kwType == tkt.KwType.COMMA || delimiter.kwType == tkt.KwType.NEWLINE:
            p.consume()
        elif delimiter.kwType != tkt.KwType.PAREN_CL:
            try nonFatalError(p, "ENUM_DELIMITER", "expected delimiter between enum variants", "expected: comma, newline, or )", delimiter.pos)
            try skipToListBoundary(p, tkt.KwType.PAREN_CL)
        ..
    ..
    if variants.count() == 0:
        try nonFatalError(p, "EMPTY_ENUM", "enum must declare at least one value", "", nameTk.pos)
    ..
    isPublic := p.pendingPublic
    p.pendingPublic = false
    ret try makeGlStmt(p, nt.GlobalStmt.Enum(id=registered.id, name=nameTk.repr, scopeId=scope.id, backing=backing, variants=move variants, isPublic=isPublic))
..

registerParsedDecl(p Parser*, name str, kind decl.DeclKind, pos org.FilePos) !decl.Decl*:
    declNameIdx, declNameErr := p.module.names.indexOf(name)
    if declNameErr.ok():
        try errorFatal(p, "DUPLICATE_DECL", "declaration name is already registered in this module", "declaration names must be unique", pos)
    ..
    ret try p.module.registerDecl(name, kind)
..

registerHeaderArgs(p Parser*, header nt.Header*, kind decl.ScopeKind) !void:
    scope := try p.module.registerScope(kind)
    header.scopeId = scope.id
    p.scope = scope
    for i := 0 to header.fields.count():
        field := try header.fields.get(i)
        localField nt.Expr
        unsafe localField = *field
        match localField as argument:
        case nt.Expr.VarDef:
            argumentNameIdx, argumentNameErr := scope.names.indexOf(argument.name)
            if argumentNameErr.ok():
                try nonFatalError(p, "DUPLICATE_ARGUMENT", "argument name is repeated in the function header", "argument names must be unique", p.currPos())
            else:
                registered := try scope.registerDecl(argument.name, decl.DeclKind.Argument(name=argument.name, type=argument.type, boundedCount=argument.boundedCount))
                registeredField := try makeExpr(p, nt.Expr.VarDef(type=argument.type, name=argument.name, declId=registered.id, boundedCount=argument.boundedCount))
                try header.fields.set(i, registeredField)
            ..
        else:
            try errorFatal(p, "INVALID_HEADER_FIELD", "function header contains a non-variable field", "expected a typed argument declaration", p.currPos())
        ..
    ..
..

registerHeaderFields(p Parser*, header nt.Header*) !void:
    scope := try p.module.registerScope(decl.ScopeKind.Block())
    header.scopeId = scope.id
    for i := 0 to header.fields.count():
        field := try header.fields.get(i)
        localField nt.Expr
        unsafe localField = *field
        match localField as member:
        case nt.Expr.VarDef:
            fieldNameIdx, fieldNameErr := scope.names.indexOf(member.name)
            if fieldNameErr.ok():
                try nonFatalError(p, "DUPLICATE_FIELD", "field name is repeated in the declaration", "field names must be unique", p.currPos())
            else:
                registered := try scope.registerDecl(member.name, decl.DeclKind.Field(name=member.name, type=member.type))
                registeredField := try makeExpr(p, nt.Expr.VarDef(type=member.type, name=member.name, declId=registered.id, boundedCount=""))
                try header.fields.set(i, registeredField)
            ..
        else:
            try errorFatal(p, "INVALID_HEADER_FIELD", "declaration header contains a non-variable field", "expected a typed field declaration", p.currPos())
        ..
    ..
..

registerLocalDecl(p Parser*, name str, type nt.Type*, pos org.FilePos) !u64:
    if p.scope == none:
        ret 0
    ..
    localNameIdx, localNameErr := p.scope.names.indexOf(name)
    if localNameErr.ok():
        try errorFatal(p, "DUPLICATE_LOCAL", "local declaration name is already used in this scope", "local names must be unique within a scope", pos)
    ..
    registered := try p.scope.registerDecl(name, decl.DeclKind.Variable(name=name, type=type))
    ret registered.id
..

parseUseDecl(p Parser*, isPublic bool, prune bool) !void:
    usePos := p.currPos()
    if p.pendingGlobal || p.pendingConst || p.pendingNoCtx || p.pendingDestructor:
        try nonFatalError(p, "USE_MODIFIER", "only pub may modify a use directive", "", usePos)
    ..
    p.pendingPublic = false
    p.pendingGlobal = false
    p.pendingConst = false
    p.pendingNoCtx = false
    p.pendingDestructor = false
    p.consume()

    if p.idx >= p.file.tokens.count():
        try nonFatalError(p, "USE_PATH", "expected file path after 'use'", "expected: use \"<filepath>\" [as] <alias>", usePos)
        ret
    ..
    pathTk := try p.peek()
    pathErr := ensureTkType(p, pathTk, tkt.TkType.LIT_STR, "expected file path after 'use'", "expected: use \"<filepath>\" [as] <alias>")
    if pathErr.nok():
        try nonFatalError(p, "USE_PATH", "expected file path after 'use'", "expected: use \"<filepath>\" [as] <alias>", pathTk.pos)
        try skipToLineEnd(p)
        ret
    ..
    p.consume()

    if p.idx >= p.file.tokens.count():
        try nonFatalError(p, "USE_ALIAS", "expected alias after file path in 'use' statement", "expected: <alias>", pathTk.pos)
        ret
    ..
    aliasTk := try p.peek()
    if aliasTk.kwType == tkt.KwType.AS:
        p.consume()
        if p.idx >= p.file.tokens.count():
            try nonFatalError(p, "USE_ALIAS", "expected alias after file path in 'use' statement", "expected: <alias>", aliasTk.pos)
            ret
        ..
        aliasTk = try p.peek()
    ..
    aliasErr := ensureTkType(p, aliasTk, tkt.TkType.NAME, "expected alias after file path in 'use' statement", "expected: <alias>")
    if aliasErr.nok():
        try nonFatalError(p, "USE_ALIAS", "expected alias after file path in 'use' statement", "expected: <alias>", aliasTk.pos)
        try skipToLineEnd(p)
        ret
    ..
    p.consume()

    if p.idx < p.file.tokens.count():
        end := try p.peek()
        endErr := ensureKwType(p, end, tkt.KwType.NEWLINE, "expected end of line after use declaration", "expected: newline")
        if endErr.nok():
            try nonFatalError(p, "USE_TRAILING_TOKENS", "unexpected tokens after use declaration", "use declarations must end at the newline", end.pos)
            try skipToLineEnd(p)
            ret
        ..
        p.consume()
    ..

    if prune:
        ret
    ..

    aliasIdx, aliasErr2 := p.file.importAlias.indexOf(aliasTk.repr)
    if aliasErr2.ok():
        try nonFatalError(p, "DUPLICATE_IMPORT_ALIAS", "already using a module with this alias", "cannot reuse module aliases within the same file", aliasTk.pos)
        ret
    ..

    fromDir := try path.parent(p.file.path)
    defer fromDir.free()

    absPath := try mk_abs.makeAbsolute(pathTk.repr, fromDir)
    defer absPath.free()

    existingImportCount := p.file.imports.count()

    for i := 0 to existingImportCount:
        imported := try p.file.imports.get(i)
        if strgs.compare(imported, absPath):
            try nonFatalError(p, "DUPLICATE_IMPORT", "already using this module in the file", "cannot use the same module multiple times", pathTk.pos)
            ret
        ..
    ..

    pathCopy := try strgs.copy(absPath)
    try p.file.imports.pushRight(move pathCopy)
    storedPath := try p.file.imports.get(existingImportCount)

    try p.file.importAlias.set(aliasTk.repr, try strgs.copy(storedPath))
    if isPublic:
        try p.file.publicImportAlias.setBorrowed(aliasTk.repr, true)
    ..

    # Reserve the path while holding the same lock used by pipeline registration.
    # This prevents parallel importers from both starting a pipeline before the
    # first pipeline has opened and registered the file.
    gl.lockFiles.lock()
    onerror gl.lockFiles.unlock()
    _, fileErr := gl.files.indexOf(absPath)
    if fileErr.ok():
        gl.lockFiles.unlock()
        ret
    ..
    try gl.files.setBorrowed(absPath, none)
    gl.lockFiles.unlock()

    # Start the imported file pipeline as soon as the complete directive is parsed.
    future := try gl.pipelineRunner(storedPath)
    gl.lockPipelines.lock()
    defer gl.lockPipelines.unlock()
    try gl.pipelines.set(storedPath, move future)
..

pub run(f fctx.FileCtx*) !void:
    pCtx := try initCtx(f)
    p := addrof pCtx
    defer printErrors(p)

    f.astRoot = nt.Root(statements=nt.emptyNodeArray[nt.GlobalStmt*]())
    root := addrof f.astRoot

    max := f.tokens.count()
    loop p.idx < max:
        if p.pruneNext:
            try p.parsePrunedGlobal()
            p.pruneNext = false
        else:
            glStmt := try parseGlobalStmt(p)
            if glStmt != none:
                try root.statements.pushRight(ctx.alloc, glStmt)
            ..
        ..
    ..

    if p.errors.count() != 0:
        throw "parser encountered errors"
    ..
..

initCtx(f fctx.FileCtx*) !Parser:
    try decl.initResolver()
    module := try decl.registerModule(f.path)

    ret Parser(
        file=f,
        module=module,
        scope=none,
        idx=0,
        currTokIdx=0,
        currTok=mem.zeroValue[tkt.Token](),
        errors=try ls.new[comperr.CompErr](ctx.alloc, none),
        moduleSeen=false,
        pendingPublic=false,
        pendingGlobal=false,
        pendingConst=false,
        pendingNoCtx=false,
        pendingDestructor=false,
        pruneNext=false,
    )
..
