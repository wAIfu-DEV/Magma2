mod llvm_cache_fingerprint

# Stable serialization of module declarations and implementation bodies that
# can affect lowering in an importing module. Bodies are serialized once per
# module; references between declarations use stable identities.

use "std:builder" builder
use "std:strconv" strconv
use "std:strings" strings
use "std:sha1" sha1
use "std:slices" slices
use "std:list" ls
use "std:sort" sort
use "std:fs" fs
use "std:hash_map" hm
use "std:read_write_lock" rwlock

use "shared/filectx" fctx
use "shared/node_types" nt
use "decl_resolver" dclr
use "shared/global" gl

pub FingerprintCache(
    values hm.HashMap[str]
    lock rwlock.ReadWriteLock
)

cleanupFingerprintValue(value $str) void:
    value.free()
..

pub newFingerprintCache() !$FingerprintCache:
    ret FingerprintCache(values=try hm.new[str](32, cleanupFingerprintValue), lock=rwlock.new())
..

destr FingerprintCache.close() void:
    this.values.free()
..

pub FingerprintCache.store(filePath str, value str) !void:
    this.lock.writeLock()
    defer this.lock.writeUnlock()
    if this.values.contains(filePath) == false:
        try this.values.set(filePath, try strings.copy(value))
    ..
..

cachedFingerprint(cache FingerprintCache*, file fctx.FileCtx*) !$str:
    cache.lock.readLock()
    defer cache.lock.readUnlock()
    if cache.values.contains(file.path):
        value := try cache.values.get(file.path)
        ret try strings.copy(value)
    ..
    ret try fingerprint(file)
..

field(out builder.Builder*, value str) !void:
    length := try strconv.formatUint(value.countBytes())
    defer length.free()
    try out.appendCopy(length)
    try out.appendBorrowed(":")
    try out.appendCopy(value)
    try out.appendBorrowed(";")
..

number(out builder.Builder*, value u64) !void:
    text := try strconv.formatUint(value)
    defer text.free()
    try field(out, text)
..

boolean(out builder.Builder*, value bool) !void:
    if value:
        try field(out, "true")
    else:
        try field(out, "false")
    ..
..

declIdentity(out builder.Builder*, declaration dclr.Decl*) !void:
    if declaration == none:
        try field(out, "<unresolved>")
        ret
    ..
    try field(out, declaration.module.path)
    match declaration.kind as kind:
    case dclr.DeclKind.Module:
        try field(out, kind.name)
    case dclr.DeclKind.Variable:
        try field(out, kind.name)
    case dclr.DeclKind.Argument:
        try field(out, kind.name)
    case dclr.DeclKind.Field:
        try field(out, kind.name)
    case dclr.DeclKind.Function:
        try field(out, kind.name)
    case dclr.DeclKind.Struct:
        try field(out, kind.name)
    case dclr.DeclKind.Alias:
        try field(out, kind.name)
    case dclr.DeclKind.Union:
        try field(out, kind.name)
    case dclr.DeclKind.Enum:
        try field(out, kind.name)
    case dclr.DeclKind.Proto:
        try field(out, kind.name)
    case dclr.DeclKind.UnionVariant:
        try field(out, kind.name)
    case dclr.DeclKind.EnumVariant:
        try field(out, kind.name)
    case dclr.DeclKind.TypeParameter:
        try field(out, kind.name)
        try number(out, kind.index)
    ..
..

appendType(out builder.Builder*, type nt.Type*, depth u64) !void:
    if type == none || depth > 64:
        try field(out, "type-none-or-too-deep")
        ret
    ..
    match type as value:
    case nt.Type.Named:
        try field(out, "named")
        try declIdentity(out, value.decl)
    case nt.Type.Pointer:
        try field(out, "pointer")
        try appendType(out, value.toType, depth + 1)
    case nt.Type.Templated:
        try field(out, "templated")
        try appendType(out, value.owner, depth + 1)
        try number(out, value.args.count())
        for i := 0 to value.args.count():
            try appendType(out, value.args.get(i), depth + 1)
        ..
    case nt.Type.Slice:
        try field(out, "slice")
        try appendType(out, value.ofType, depth + 1)
    case nt.Type.Owned:
        try field(out, "owned")
        try appendType(out, value.ofType, depth + 1)
    case nt.Type.Throwing:
        try field(out, "throwing")
        try appendType(out, value.ofType, depth + 1)
    case nt.Type.Function:
        try field(out, "function")
        try boolean(out, value.noContext)
        try number(out, value.args.count())
        for i := 0 to value.args.count():
            try appendType(out, value.args.get(i), depth + 1)
        ..
        try appendType(out, value.returnType, depth + 1)
    case nt.Type.CompilerKnown:
        try field(out, "compiler-known")
        try field(out, value.name)
    case nt.Type.Void:
        try field(out, "void")
    ..
..

appendHeader(out builder.Builder*, header nt.Header*) !void:
    if header == none:
        try field(out, "header-none")
        ret
    ..
    try field(out, header.name)
    try number(out, header.fields.count())
    for i := 0 to header.fields.count():
        fieldExpr := try header.fields.get(i)
        match fieldExpr as argument:
        case nt.Expr.VarDef:
            try field(out, argument.name)
            try appendType(out, argument.type, 0)
        else:
            try field(out, "invalid-header-field")
        ..
    ..
    match header.kind as kind:
    case nt.HeaderKind.Plain:
        try field(out, "plain")
    case nt.HeaderKind.Templated:
        try field(out, "template")
        try number(out, kind.typeArgs.count())
        for i := 0 to kind.typeArgs.count():
            try appendType(out, kind.typeArgs.get(i), 0)
        ..
    ..
..

appendExpr(out builder.Builder*, expression nt.Expr*, depth u64) !void:
    if expression == none || depth > 128:
        try field(out, "expr-none-or-too-deep")
        ret
    ..
    match expression as value:
    case nt.Expr.Empty:
        try field(out, "empty")
    case nt.Expr.Literal:
        try field(out, "literal")
        match value.literal as literal:
        case nt.Literal.None:
            try field(out, "none")
        case nt.Literal.String:
            try field(out, "string")
            try field(out, literal.value)
        case nt.Literal.Number:
            try field(out, "number")
            try field(out, literal.value)
        case nt.Literal.HexNumber:
            try field(out, "hex")
            try field(out, literal.value)
        case nt.Literal.Boolean:
            try boolean(out, literal.value)
        case nt.Literal.Char8:
            try field(out, literal.value)
        case nt.Literal.Char32:
            try field(out, literal.value)
        ..
    case nt.Expr.Named:
        try field(out, "named-expr")
        try declIdentity(out, value.decl)
    case nt.Expr.MemberAccess:
        try field(out, "member")
        try appendExpr(out, value.owner, depth + 1)
        try appendExpr(out, value.member, depth + 1)
    case nt.Expr.Subscript:
        try field(out, "subscript")
        try boolean(out, value.genericReference)
        if value.genericReference:
            try appendType(out, value.genericTypeArg, depth + 1)
        ..
        try appendExpr(out, value.owner, depth + 1)
        try appendExpr(out, value.index, depth + 1)
    case nt.Expr.Array:
        try field(out, "array")
        try boolean(out, value.inferLength)
        try appendExpr(out, value.length, depth + 1)
    case nt.Expr.Embed:
        try field(out, "embed")
        try field(out, value.path)
        embedded := try fs.readFile(value.path)
        defer embedded.free()
        payloadDigest := try digestString(embedded)
        defer payloadDigest.free()
        try field(out, payloadDigest)
    case nt.Expr.CompilerKnown:
        try field(out, "compiler-known")
        try field(out, value.name)
    case nt.Expr.InlineLLVM:
        try field(out, "inline-llvm")
        try field(out, value.operation)
        try appendType(out, value.type, 0)
        try number(out, value.args.count())
        for i := 0 to value.args.count():
            try appendExpr(out, value.args.get(i), depth + 1)
        ..
    case nt.Expr.VarDef:
        try field(out, "var")
        try field(out, value.name)
        try appendType(out, value.type, 0)
    case nt.Expr.VarDefAssign:
        try field(out, "var-assign")
        try field(out, value.name)
        try appendType(out, value.type, 0)
        try appendExpr(out, value.assignment, depth + 1)
    case nt.Expr.VarDefAssignDestructure:
        try field(out, "var-destructure")
        try field(out, value.nameValue)
        try field(out, value.nameError)
        try appendExpr(out, value.call, depth + 1)
    case nt.Expr.Sizeof:
        try field(out, "sizeof")
        try appendType(out, value.operand, 0)
    case nt.Expr.Unary:
        try field(out, "unary")
        try number(out, value.op)
        try appendExpr(out, value.operand, depth + 1)
    case nt.Expr.Move:
        try field(out, "move")
        try appendExpr(out, value.operand, depth + 1)
    case nt.Expr.Binary:
        try field(out, "binary")
        try number(out, value.op)
        try appendExpr(out, value.left, depth + 1)
        try appendExpr(out, value.right, depth + 1)
    case nt.Expr.DirectCall:
        try field(out, "direct-call")
        try declIdentity(out, value.decl)
        try appendArgs(out, value.args, depth + 1)
    case nt.Expr.TemplatedDirectCall:
        try field(out, "templated-direct-call")
        try declIdentity(out, value.decl)
        try appendArgs(out, value.args, depth + 1)
        try number(out, value.typeArgs.count())
        for i := 0 to value.typeArgs.count():
            try appendType(out, value.typeArgs.get(i), 0)
        ..
    case nt.Expr.IndirectCall:
        try field(out, "indirect-call")
        try appendExpr(out, value.owner, depth + 1)
        try appendArgs(out, value.args, depth + 1)
    case nt.Expr.TemplatedIndirectCall:
        try field(out, "templated-indirect-call")
        try appendExpr(out, value.owner, depth + 1)
        try appendArgs(out, value.args, depth + 1)
        try number(out, value.typeArgs.count())
        for i := 0 to value.typeArgs.count():
            try appendType(out, value.typeArgs.get(i), 0)
        ..
    case nt.Expr.GenericApply:
        try field(out, "generic-apply")
        try appendType(out, value.type, 0)
        try appendExpr(out, value.owner, depth + 1)
        try number(out, value.typeArgs.count())
        for i := 0 to value.typeArgs.count():
            try appendType(out, value.typeArgs.get(i), 0)
        ..
    case nt.Expr.Try:
        try field(out, "try")
        try appendExpr(out, value.call, depth + 1)
    case nt.Expr.Assign:
        try field(out, "assign")
        try appendExpr(out, value.assignee, depth + 1)
        try appendExpr(out, value.expr, depth + 1)
    case nt.Expr.Return:
        try field(out, "return")
        try appendExpr(out, value.expr, depth + 1)
    case nt.Expr.Throw:
        try field(out, "throw")
        try appendExpr(out, value.expr, depth + 1)
    ..
..

appendArgs(out builder.Builder*, args nt.NodeArray[nt.Expr*], depth u64) !void:
    try number(out, args.count())
    for i := 0 to args.count():
        try appendExpr(out, args.get(i), depth + 1)
    ..
..

appendStmt(out builder.Builder*, statement nt.Stmt*, depth u64) !void:
    if statement == none || depth > 128:
        try field(out, "stmt-none-or-too-deep")
        ret
    ..
    match statement as value:
    case nt.Stmt.Body:
        try field(out, "body")
        try number(out, value.statements.count())
        for i := 0 to value.statements.count():
            try appendStmt(out, value.statements.get(i), depth + 1)
        ..
    case nt.Stmt.Expression:
        try field(out, "expression-stmt")
        try appendExpr(out, value.expr, depth + 1)
    case nt.Stmt.Break:
        try field(out, "break")
    case nt.Stmt.Continue:
        try field(out, "continue")
    case nt.Stmt.Defer:
        try field(out, "defer")
        try appendExpr(out, value.expr, depth + 1)
        try appendStmt(out, value.body, depth + 1)
    case nt.Stmt.OnError:
        try field(out, "onerror")
        try appendExpr(out, value.expr, depth + 1)
        try appendStmt(out, value.body, depth + 1)
    case nt.Stmt.Unsafe:
        try field(out, "unsafe")
        try appendExpr(out, value.expr, depth + 1)
        try appendStmt(out, value.body, depth + 1)
    case nt.Stmt.Bounded:
        try field(out, "bounded")
        try appendArgs(out, value.predicates, depth + 1)
        try appendArgs(out, value.pointers, depth + 1)
        try appendArgs(out, value.extents, depth + 1)
        try appendStmt(out, value.body, depth + 1)
    case nt.Stmt.Match:
        try field(out, "match")
        try appendExpr(out, value.expression, depth + 1)
        try field(out, value.binding)
        try number(out, value.cases.count())
        for i := 0 to value.cases.count():
            item := try value.cases.get(i)
            try appendName(out, item.variant)
            try appendStmt(out, item.body, depth + 1)
        ..
        try appendStmt(out, value.elseBody, depth + 1)
    case nt.Stmt.LLVM:
        try field(out, "llvm-stmt")
        try field(out, value.text)
    case nt.Stmt.If:
        try field(out, "if")
        try appendExpr(out, value.condition, depth + 1)
        try appendStmt(out, value.body, depth + 1)
        try appendStmt(out, value.next, depth + 1)
    case nt.Stmt.Elif:
        try field(out, "elif")
        try appendExpr(out, value.condition, depth + 1)
        try appendStmt(out, value.body, depth + 1)
        try appendStmt(out, value.next, depth + 1)
    case nt.Stmt.Else:
        try field(out, "else")
        try appendStmt(out, value.body, depth + 1)
    case nt.Stmt.Loop:
        try field(out, "loop")
        try appendExpr(out, value.condition, depth + 1)
        try appendStmt(out, value.body, depth + 1)
    case nt.Stmt.ForLoop:
        try field(out, "for")
        try appendExpr(out, value.index, depth + 1)
        try appendExpr(out, value.bound, depth + 1)
        try appendStmt(out, value.body, depth + 1)
    ..
..

appendName(out builder.Builder*, name nt.Name*) !void:
    if name == none:
        try field(out, "name-none")
        ret
    ..
    match name as value:
    case nt.Name.Simple:
        try field(out, value.name)
    case nt.Name.Composite:
        for i := 0 to value.names.count():
            try field(out, value.names.get(i))
        ..
    ..
..

appendGlobal(out builder.Builder*, statement nt.GlobalStmt*) !void:
    match statement as value:
    case nt.GlobalStmt.Struct:
        if value.isPublic == false:
            ret
        ..
        try field(out, "public-struct")
        try appendHeader(out, value.header)
        try number(out, value.implements.count())
        for i := 0 to value.implements.count():
            try appendType(out, value.implements.get(i), 0)
        ..
    case nt.GlobalStmt.Function:
        if value.isPublic == false:
            ret
        ..
        try field(out, "public-function")
        try appendHeader(out, value.header)
        try appendType(out, value.retType, 0)
        try boolean(out, value.noContext)
        isGeneric bool = false
        if value.header.decl != none:
            match value.header.decl.kind as functionKind:
            case dclr.DeclKind.Function:
                isGeneric = functionKind.typeParams.count() != 0
            else:
                ret
            ..
        ..
        if isGeneric:
            try appendStmt(out, value.body, 0)
        else:
            # A non-generic function body stays behind its stable symbol.
            ret
        ..
    case nt.GlobalStmt.ExternalFunction:
        if value.isPublic == false:
            ret
        ..
        try field(out, "public-external")
        try field(out, value.externalName)
        try appendHeader(out, value.header)
        try appendType(out, value.retType, 0)
        try boolean(out, value.noContext)
    case nt.GlobalStmt.Variable:
        if value.isPublic == false:
            ret
        ..
        try field(out, "public-variable")
        try field(out, value.name)
        try appendType(out, value.type, 0)
        try boolean(out, value.isGlobal)
        try boolean(out, value.isConst)
        if value.isConst:
            try appendExpr(out, value.initializer, 0)
        ..
    case nt.GlobalStmt.Alias:
        if value.isPublic == false:
            ret
        ..
        try field(out, "public-alias")
        try appendName(out, value.name)
        try appendType(out, value.type, 0)
    case nt.GlobalStmt.Method:
        try field(out, "method-owner")
        try appendType(out, value.ownerType, 0)
        try appendName(out, value.name)
        try appendGlobal(out, value.methodBody)
    case nt.GlobalStmt.Union:
        if value.isPublic == false:
            ret
        ..
        try field(out, "public-union")
        try field(out, value.name)
        try number(out, value.implements.count())
        for i := 0 to value.implements.count():
            try appendType(out, value.implements.get(i), 0)
        ..
        try number(out, value.variants.count())
        for i := 0 to value.variants.count():
            variant := try value.variants.get(i)
            try appendHeader(out, variant)
        ..
    case nt.GlobalStmt.Enum:
        if value.isPublic == false:
            ret
        ..
        try field(out, "public-enum")
        try field(out, value.name)
        try appendType(out, value.backing, 0)
        try number(out, value.variants.count())
        for i := 0 to value.variants.count():
            try appendExpr(out, value.variants.get(i), 0)
        ..
    case nt.GlobalStmt.Proto:
        if value.isPublic == false:
            ret
        ..
        try field(out, "public-proto")
        try field(out, value.name)
        try number(out, value.implements.count())
        for i := 0 to value.implements.count():
            try appendType(out, value.implements.get(i), 0)
        ..
        try number(out, value.methods.count())
        for i := 0 to value.methods.count():
            method := try value.methods.get(i)
            try appendHeader(out, method.header)
            try appendType(out, method.returnType, 0)
            try boolean(out, method.noContext)
        ..
    case nt.GlobalStmt.LLVM:
        # LLVM text is private implementation in its owning file. Public
        # consumers refer to its symbols through declarations.
        ret
    case nt.GlobalStmt.Embed:
        ret
    ..
..

pub fingerprint(file fctx.FileCtx*) !$str:
    output := try builder.new()
    defer output.free()
    for i := 0 to file.astRoot.statements.count():
        statement := try file.astRoot.statements.get(i)
        try appendGlobal(addrof output, statement)
        # Dependency cache keys must change when implementation details used by
        # generic specializations change. Serialize each local body once here;
        # call expressions encode declarations by identity and never inline
        # another declaration's body.
        try appendLocalBodies(addrof output, statement)
    ..
    serialized := try output.build()
    defer serialized.free()
    ret try digestString(serialized)
..

appendDependencyGraph(out builder.Builder*, file fctx.FileCtx*, visited ls.List[str]*, cache FingerprintCache*) !void:
    for i := 0 to visited.count():
        prior := try visited.get(i)
        if strings.compare(prior, file.path):
            ret
        ..
    ..
    ownedPath := try strings.copy(file.path)
    try visited.pushRight(move ownedPath)
    interface := try cachedFingerprint(cache, file)
    defer interface.free()
    try field(out, file.path)
    try field(out, interface)
    for i := 0 to file.imports.count():
        importedPath := try file.imports.get(i)
        importedFile := try gl.files.get(importedPath)
        try appendDependencyGraph(out, importedFile, visited, cache)
    ..
..

pub dependenciesFingerprint(file fctx.FileCtx*, cache FingerprintCache*) !$str:
    output := try builder.new()
    defer output.free()
    visited := try ls.new[str](ctx.alloc, none)
    defer visited.free()
    for i := 0 to file.imports.count():
        importedPath := try file.imports.get(i)
        importedFile := try gl.files.get(importedPath)
        try appendDependencyGraph(addrof output, importedFile, addrof visited, cache)
    ..
    serialized := try output.build()
    defer serialized.free()
    ret try digestString(serialized)
..

compareVisibleFiles(a fctx.FileCtx*, b fctx.FileCtx*) i64:
    aLength := a.path.countBytes()
    bLength := b.path.countBytes()
    commonLength := aLength
    if bLength < commonLength:
        commonLength = bLength
    ..
    for i := 0 to commonLength:
        aByte := strings.byteAt(a.path, i)
        bByte := strings.byteAt(b.path, i)
        if aByte < bByte:
            ret -1
        ..
        if aByte > bByte:
            ret 1
        ..
    ..
    if aLength < bLength:
        ret -1
    ..
    if aLength > bLength:
        ret 1
    ..
    ret 0
..

pub visibleImplementationsFingerprint() !$str:
    visibleFiles := try ls.new[fctx.FileCtx*](ctx.alloc, none)
    defer visibleFiles.free()
    for i := 0 to gl.importedFiles.count():
        try visibleFiles.pushRight(try gl.importedFiles.get(i))
    ..
    sort.quick[fctx.FileCtx*](visibleFiles.view(), compareVisibleFiles)
    output := try builder.new()
    defer output.free()
    try field(addrof output, "visible-proto-implementations")
    try number(addrof output, visibleFiles.count())
    for i := 0 to visibleFiles.count():
        visibleFile := try visibleFiles.get(i)
        try field(addrof output, visibleFile.path)
        sourceDigest := try digestString(visibleFile.content)
        defer sourceDigest.free()
        try field(addrof output, sourceDigest)
    ..
    serialized := try output.build()
    defer serialized.free()
    ret try digestString(serialized)
..

compareFingerprintStrings(a str, b str) i64:
    aLength := a.countBytes()
    bLength := b.countBytes()
    commonLength := aLength
    if bLength < commonLength:
        commonLength = bLength
    ..
    for i := 0 to commonLength:
        aByte := strings.byteAt(a, i)
        bByte := strings.byteAt(b, i)
        if aByte < bByte:
            ret -1
        ..
        if aByte > bByte:
            ret 1
        ..
    ..
    if aLength < bLength:
        ret -1
    ..
    if aLength > bLength:
        ret 1
    ..
    ret 0
..

specializationFingerprint(specialization nt.Specialization*) !$str:
    output := try builder.new()
    defer output.free()
    try field(addrof output, "specialization")
    try declIdentity(addrof output, specialization.template)
    try boolean(addrof output, specialization.isFunction)
    try number(addrof output, specialization.typeArgs.count())
    for i := 0 to specialization.typeArgs.count():
        try appendType(addrof output, specialization.typeArgs.get(i), 0)
    ..
    try appendType(addrof output, specialization.concreteType, 0)
    ret try output.build()
..

appendLocalBodies(out builder.Builder*, statement nt.GlobalStmt*) !void:
    match statement as value:
    case nt.GlobalStmt.Function:
        try field(out, "local-function-body")
        try appendStmt(out, value.body, 0)
    case nt.GlobalStmt.Method:
        try appendLocalBodies(out, value.methodBody)
    case nt.GlobalStmt.Variable:
        try field(out, "local-initializer")
        try appendExpr(out, value.initializer, 0)
    else:
        ret
    ..
..

pub loweringInputsFingerprint(file fctx.FileCtx*, cache FingerprintCache*, visibleFingerprint str) !$str:
    output := try builder.new()
    defer output.free()
    dependencies := try dependenciesFingerprint(file, cache)
    defer dependencies.free()
    try field(addrof output, dependencies)
    # Protocol payload sizes can depend on implementations outside this
    # module's dependency closure. The shared, path-sorted source fingerprint
    # is computed once per compilation and included here.
    try field(addrof output, visibleFingerprint)
    for i := 0 to file.astRoot.statements.count():
        try appendLocalBodies(addrof output, file.astRoot.statements.get(i))
    ..
    specializationKeys := try ls.new[str](ctx.alloc, none)
    defer specializationKeys.free()
    for i := 0 to file.specializations.count():
        specialization := try file.specializations.get(i)
        try specializationKeys.pushRight(try specializationFingerprint(specialization))
    ..
    sort.quick[str](specializationKeys.view(), compareFingerprintStrings)
    try number(addrof output, specializationKeys.count())
    for i := 0 to specializationKeys.count():
        key := try specializationKeys.get(i)
        try field(addrof output, key)
        key.free()
    ..
    serialized := try output.build()
    defer serialized.free()
    ret try digestString(serialized)
..

digestString(value str) !$str:
    input u8[] = slices.fromPtr(strings.toPtr(value), value.countBytes())
    digest := try sha1.sum(input)
    defer slices.free(digest)
    result := try strings.alloc(40)
    data := strings.toPtr(result)
    unsafe:
        for i u64 = 0 to 20:
            byte := digest[i]
            data[i * 2] = hexByte(byte >> 4)
            data[i * 2 + 1] = hexByte(byte & 15)
        ..
    ..
    ret move result
..

hexByte(value u8) u8:
    if value < 10:
        ret value + 48
    ..
    ret value - 10 + 97
..
