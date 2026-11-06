mod parser

use "std:memory" mem
use "std:list" ls
use "std:array" arr
use "std:stable_list" sl
use "std:cast" cast
use "std:slices" slices
use "std:footgun" fg

use "shared/filectx" fctx
use "shared/token_types" tkt
use "shared/node_types" nt
use "shared/comperr" comperr
use "shared/origin" org
use "decl_resolver" decl

Parser(
    file fctx.FileCtx*,
    module decl.Module*,
    idx u64,
    currTokIdx u64,
    currTok tkt.Token,
    errors ls.List[comperr.CompErr],
    backing sl.StableList[nt.Node],
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
    ret none
..

consumeNewLines(p Parser*) !void:
    loop true:
        t := try p.peek()
        if t.kwType == tkt.KwType.NEWLINE:
            p.consume()
        ..
    ..
..

consumeListSeparators(p Parser*, end tkt.KwType) !void:
    foundComma := false
    atLeastOne := false

    loop true:
        t := try p.peek()
        err := ensureTkType(p, t, tkt.TkType.KEYWORD, "unexpected token while expected list element delimiter", "expected: comma and/or newline")
        if err.nok() && not atLeastOne:
            throw err
        elif err.nok() && atLeastOne:
            ret
        ..

        if t.kwType == tkt.KwType.COMMA && not foundComma:
            atLeastOne = true
            foundComma = true
            p.consume()
        elif t.kwType == tkt.KwType.NEWLINE:
            atLeastOne = true
            p.consume()
        elif t.kwType == tkt.KwType.COMMA && foundComma:
            try ensureKwType(p, t, tkt.KwType.NONE, "consecutive commas in list are forbidden", "")
        elif t.kwType == end:
            ret
        else:
            try ensureKwType(p, t, tkt.KwType.NONE, "unexpected token while expected list element delimiter", "expected: comma and/or newline")
        ..
    ..
..

# The backing list owns every AST node. Children are parsed/allocated first,
# then their pointers are installed in the parent before it is appended.
makeNode[T](p Parser*, value nt.Node) !T*:
    id := try p.backing.push(move value)
    node := try p.backing.get(id)
    ret try node.implBorrow[T]()
..

makeExpr(p Parser*, value nt.Expr) !nt.Expr*:
    ret try makeNode[nt.Expr](p, value.proto())
..

makeName(p Parser*, value nt.Name) !nt.Name*:
    ret try makeNode[nt.Name](p, value.proto())
..

binaryPrecedence(t tkt.Token) u8:
    if t.type != tkt.TkType.KEYWORD:
        ret 0
    ..
    if t.kwType == tkt.KwType.ASTERIX || t.kwType == tkt.KwType.SLASH || t.kwType == tkt.KwType.PERCENT:
        ret 70
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
        op := try p.peek()
        # Postfix member selection binds more tightly than every infix
        # operator and is applied to the complete expression on its left.
        if op.kwType == tkt.KwType.DOT:
            if 90 < minPrec:
                ret left
            ..
            p.consume()
            memberTk := try p.peek()
            try ensureTkType(p, memberTk, tkt.TkType.NAME, "expected member name after '.'", "expected: <name>")
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
            left = try makeExpr(p, nt.Expr.IndirectCall(
                type=none, owner=left, args=args,
                typeArgs=arr.new[nt.Type*](ctx.alloc),
            ))
            continue
        ..
        prec := binaryPrecedence(op)
        if prec == 0 || prec < minPrec:
            ret left
        ..

        p.consume()
        right := try parseExpression(p, prec + 1)
        left = try makeExpr(p, nt.Expr.Binary(type=none, op=cast.u64to8(op.kwType), left=left, right=right))
    ..
..

parseCallArgs(p Parser*) !arr.Array[nt.Expr*]:
    opening := try p.peek()
    try ensureKwType(p, opening, tkt.KwType.PAREN_OP, "expected opening parenthesis for call", "expected: (")
    p.consume()

    values := try arr.new[nt.Expr*](ctx.alloc)
    defer fg.drop(move values)

    t := try p.peek()
    if t.kwType != tkt.KwType.PAREN_CL:
        loop true:
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
            try ensureKwType(p, t, tkt.KwType.NONE, "expected call argument delimiter", "expected: , or )")
        ..
    ..

    closing := try p.peek()
    try ensureKwType(p, closing, tkt.KwType.PAREN_CL, "expected closing parenthesis after call arguments", "expected: )")
    p.consume()

    ret values
..

parseLiteral(p Parser*) !nt.Expr*:
    t := try p.peek()

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
    litPtr := try makeNode[nt.Literal](p, lit.proto())
    ret try makeExpr(p, nt.Expr.Literal(type=none, literal=litPtr))
..

parseExprPrefix(p Parser*) !nt.Expr*:
    t := try p.peek()

    if t.type == tkt.TkType.NAME:
        p.consume()
        ret try makeExpr(p, nt.Expr.Named(type=none, name=t.repr, declId=0))
    ..

    if t.type >= tkt.TkType.LIT_STR && t.type <= tkt.TkType.LIT_CHAR32:
        ret try parseLiteral(p)
    ..

    if t.type == tkt.TkType.KEYWORD && (t.kwType == tkt.KwType.MINUS || t.kwType == tkt.KwType.NOT || t.kwType == tkt.KwType.TILDE || t.kwType == tkt.KwType.ASTERIX || t.kwType == tkt.KwType.AMPERSAND):
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

dud[T](x T)

# Only used for single names or composite names
# Not to be used in expressions
parseName(p Parser*, allowComposite bool) !nt.Name*:
    atLeastOne := false

    # workaround since the borrow checker is an absolute fucking piece of shit
    names := try arr.new[str](ctx.alloc)

    loop true:
        t := try p.peek()
        err := ensureTkType(p, t, tkt.TkType.NAME, "unexpected token while expected name", "expected: <name>, <name>.<method>")
        
        if err.nok() && not atLeastOne:
            names.free(ctx.alloc, none)
            throw err
            ret none # TODO: make throw non-conditional
        elif err.nok() && atLeastOne:
            ret try makeName(p, nt.Name.Composite(names=move names))
        ..

        p.consume()

        if not allowComposite:
            simpleName := try names.get(0)
            node := try makeName(p, nt.Name.Simple(name=simpleName))
            names.free(ctx.alloc, none)
            ret node
        ..

        t = try p.peek()
        if t.kwType == tkt.KwType.DOT:
            p.consume()
            continue
        ..
    ..
..

parseNameSimple(p Parser*) !str:
    t := try p.peek()
    try ensureTkType(p, t, tkt.TkType.NAME, "unexpected token while expected name", "expected: <name>")
    p.consume()
    ret t.repr
..

parseVarDef(p Parser*) !nt.Expr*:
    t := try p.peek()
    name := try parseNameSimple(p)
    type := try parseType(p)
    ret try makeExpr(p, nt.Expr.VarDef(type=type, name=name))
..

parseTypedArgList(p Parser*) !arr.Array[nt.Expr*]:
    t := try p.peek()
    # ensure (
    try ensureKwType(p, t, tkt.KwType.PAREN_OP, "unexpected token while expected opening parenthesis", "expected: (")
    p.consume()

    fields := try arr.new[nt.Expr*](ctx.alloc)
    
    loop true:
        field := try parseVarDef(p)
        try fields.pushRight(ctx.alloc, field)
        try consumeListSeparators(p, tkt.KwType.PAREN_CL)
    ..
    t = try p.peek()
    try ensureKwType(p, t, tkt.KwType.PAREN_CL, "unexpected token while expected closing parenthesis", "expected: )")
    p.consume()

    ret move fields
..

parseTemplateArgs(p Parser*) !arr.Array[nt.Type*]:
    t := try p.peek()
    # ensure (
    try ensureKwType(p, t, tkt.KwType.BRACK_OP, "unexpected token while expected opening bracket", "expected: [")
    p.consume()

    types := try arr.new[nt.Type*](ctx.alloc)

    loop true:
        type := try parseType(p)
        try types.pushRight(ctx.alloc, type)
        try consumeListSeparators(p, tkt.KwType.BRACK_CL)
    ..
    t = try p.peek()
    try ensureKwType(p, t, tkt.KwType.BRACK_CL, "unexpected token while expected closing bracket", "expected: ]")
    p.consume()

    ret move types
..

parseHeader(p Parser*, name str) !nt.Header*:
    t := try p.peek()
    try ensureTkType(p, t, tkt.TkType.KEYWORD, "unexpected token while expected opening parenthesis or bracket", "expected: <name>(arg Type, ...), <name>[Type](arg Type, ...)")
    p.consume()

    header := nt.Header(id=0, name=name, fields=mem.zeroValue[arr.Array[nt.Expr*]](), typeArgs=mem.zeroValue[arr.Array[nt.Type*]]())

    # parse [T, ...]
    if t.kwType == tkt.KwType.BRACK_OP:
        header.typeArgs = try parseTemplateArgs(p)
    else:
        header.typeArgs = try arr.new[nt.Type*](ctx.alloc)
    ..
    header.fields = try parseTypedArgList(p)

    ret try makeNode[nt.Header](p, header.proto())
..

parseGlobalStmt(p Parser*) !nt.GlobalStmt*:
    t := try p.peek()

    if t.type == tkt.TkType.NAME: # could be either header or module vardef
        name := try parseName(p, true)
        localName nt.Name
        unsafe localName = *name # workaround since match doesn't work yet with pointer types

        t = try p.peek()

        match localName as n:
        case nt.Name.Composite:
            # here this can only be a method definition
            # TODO: parse method definition
        case nt.Name.Simple:
            if t.kwType == tkt.KwType.PAREN_OP || t.kwType == tkt.KwType.BRACK_OP:
                header := try parseHeader(p, n.name)

                t = try p.peek()
                if t.kwType != tkt.KwType.NEWLINE:
                    # TODO: parse function definition
                else:
                    # TODO: parse struct definition
                ..
            else:
                # only one left is module-local variable definition
                # TODO: parse expression, then check if is valid for global scope
            ..
        ..

        throw "failed to parse global statement after name"
    elif t.type == tkt.TkType.KEYWORD:
        # TODO: parse modifiers pub, global, noctx, etc
        # modifiers should be pushed to context list then applied to the next declaration

        # TODO: parse union, enum, mod, use, embed, etc
        throw "failed to parse global statement after keyword"
    else:
        try errorFatal(p, "UNEXPECTED_TOK_GL", "unexpected token in module's scope", "expected: <function name>, pub, enum, global, mod, use, link, ext, const", p.currPos())
    ..
    ret none
..

pub run(f fctx.FileCtx*) !nt.Root*:
    pCtx := try initCtx(f)
    p := addrof pCtx

    root := try makeNode[nt.Root](p, nt.Root(statements=arr.new[nt.GlobalStmt*](ctx.alloc)).proto())

    max := f.tokens.count()
    loop p.idx < max:
        glStmt := try parseGlobalStmt(p)
    ..

    unsafe: # it thinks pCtx escapes??
        ret root
    ..
..

initCtx(f fctx.FileCtx*) !Parser:
    backing := try sl.new[nt.Node](ctx.alloc, none)
    module := try decl.registerModule(f.path)

    ret Parser(
        file=f,
        module=module,
        idx=0,
        currTokIdx=0,
        currTok=mem.zeroValue[tkt.Token](),
        errors=try ls.new[comperr.CompErr](ctx.alloc, none),
        backing=move backing,
    )
..
