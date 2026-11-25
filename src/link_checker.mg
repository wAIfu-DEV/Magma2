mod link_checker
# Links parsed names to declarations and checks the complete parsed import
# graph before specialization work is drained.

use "std:strings" strgs
use "std:path" path
use "std:list" ls
use "std:errors" errs
use "std:time" time
use "std:strconv" strconv
use "std:cast" cast
use "std:slices" slices
use "std:utf8" utf8

use "shared/filectx" fctx
use "shared/global" gl
use "shared/node_types" nt
use "shared/token_types" tkt
use "shared/comperr" comperr
use "shared/origin" org
use "decl_resolver" dclr
use "compiler_known" known

const MAX_SPECIALIZATIONS u64 = 10000

Checker(
    file fctx.FileCtx*
    module dclr.Module*
    coreModule dclr.Module*
    returnType nt.Type*
    loopDepth u64
    deferDepth u64
    tryDepth u64
    bindingParams dclr.DeclArray
    bindingTypes nt.TypePointerArray
    specializations nt.SpecializationPointerArray
    errors ls.List[comperr.CompErr]
    checkingSpecialization bool
    unsafeDepth u64
    callDiagnosticPos org.FilePos
    callSignaturePos org.FilePos
    callSignatureFile fctx.FileCtx*
    hasCallDiagnostic bool
    failurePos org.FilePos
    hasFailurePos bool
)

CallResolution(kind nt.CallKind, target dclr.Decl*)

CallDiagnosticState(
    position org.FilePos
    signaturePos org.FilePos
    signatureFile fctx.FileCtx*
    active bool
)

saveCallDiagnostic(c Checker*) CallDiagnosticState:
    ret CallDiagnosticState(
        position=c.callDiagnosticPos,
        signaturePos=c.callSignaturePos,
        signatureFile=c.callSignatureFile,
        active=c.hasCallDiagnostic,
    )
..

restoreCallDiagnostic(c Checker*, state CallDiagnosticState) void:
    c.callDiagnosticPos = state.position
    c.callSignaturePos = state.signaturePos
    c.callSignatureFile = state.signatureFile
    c.hasCallDiagnostic = state.active
..

makeNodeType(c Checker*, value nt.Type) !nt.Type*:
    id := try c.file.astNodes.push(value.proto[nt.Node]())
    node := try c.file.astNodes.get(id)
    ret try node.implBorrow[nt.Type]()
..

setCallFailureContext(c Checker*, expression nt.Expr*) !void:
    if expression == none:
        ret
    ..
    c.hasCallDiagnostic = false
    c.callSignatureFile = none
    match expression as value:
    case nt.Expr.DirectCall:
        c.callDiagnosticPos = value.sourcePos
        if value.decl != none:
            c.callSignaturePos = value.decl.sourcePos
            c.callSignatureFile = try gl.files.get(value.decl.module.path)
            c.hasCallDiagnostic = true
        ..
    case nt.Expr.TemplatedDirectCall:
        c.callDiagnosticPos = value.sourcePos
        if value.decl != none:
            c.callSignaturePos = value.decl.sourcePos
            c.callSignatureFile = try gl.files.get(value.decl.module.path)
            c.hasCallDiagnostic = true
        ..
    case nt.Expr.IndirectCall:
        c.callDiagnosticPos = value.sourcePos
        declaration := callableDeclaration(expression)
        if declaration != none:
            c.callSignaturePos = declaration.sourcePos
            c.callSignatureFile = try gl.files.get(declaration.module.path)
            c.hasCallDiagnostic = true
        ..
    case nt.Expr.TemplatedIndirectCall:
        c.callDiagnosticPos = value.sourcePos
        declaration := callableDeclaration(expression)
        if declaration != none:
            c.callSignaturePos = declaration.sourcePos
            c.callSignatureFile = try gl.files.get(declaration.module.path)
            c.hasCallDiagnostic = true
        ..
    case nt.Expr.Try:
        try setCallFailureContext(c, value.call)
    case nt.Expr.Move:
        try setCallFailureContext(c, value.operand)
    else:
        c.hasCallDiagnostic = false
    ..
..

cloneName(c Checker*, source nt.Name*) !nt.Name*:
    if source == none:
        ret none
    ..
    match source as value:
    case nt.Name.Simple:
        id := try c.file.astNodes.push(nt.Name.Simple(name=value.name).proto[nt.Node]())
        node := try c.file.astNodes.get(id)
        ret try node.implBorrow[nt.Name]()
    case nt.Name.Composite:
        names := nt.emptyStringArray()
        for i := 0 to value.names.count():
            try names.pushRight(ctx.alloc, try value.names.get(i))
        ..
        id := try c.file.astNodes.push(nt.Name.Composite(names=move names).proto[nt.Node]())
        node := try c.file.astNodes.get(id)
        ret try node.implBorrow[nt.Name]()
    ..
    throw "cannot clone name node"
..

cloneType(c Checker*, source nt.Type*) !nt.Type*:
    if source == none:
        ret none
    ..
    match source as value:
    case nt.Type.Named:
        primitive := value.primitive
        if primitive == nt.PrimitiveType.Unresolved && value.name != none:
            match value.name as simpleName:
            case nt.Name.Simple:
                primitive = primitiveTypeForName(simpleName.name)
            else:
                primitive = nt.PrimitiveType.Unresolved
            ..
        ..
        ret try makeNodeType(c, nt.Type.Named(name=try cloneName(c, value.name), decl=value.decl, primitive=primitive))
    case nt.Type.Pointer:
        ret try makeNodeType(c, nt.Type.Pointer(toType=try cloneType(c, value.toType)))
    case nt.Type.Templated:
        args := nt.emptyTypeArray()
        for i := 0 to value.args.count():
            try args.pushRight(ctx.alloc, try cloneType(c, value.args.get(i)))
        ..
        ret try makeNodeType(c, nt.Type.Templated(owner=try cloneType(c, value.owner), args=move args))
    case nt.Type.Slice:
        ret try makeNodeType(c, nt.Type.Slice(ofType=try cloneType(c, value.ofType)))
    case nt.Type.Owned:
        ret try makeNodeType(c, nt.Type.Owned(ofType=try cloneType(c, value.ofType)))
    case nt.Type.Throwing:
        ret try makeNodeType(c, nt.Type.Throwing(ofType=try cloneType(c, value.ofType)))
    case nt.Type.Function:
        args := nt.emptyTypeArray()
        for i := 0 to value.args.count():
            try args.pushRight(ctx.alloc, try cloneType(c, value.args.get(i)))
        ..
        ret try makeNodeType(c, nt.Type.Function(args=move args, returnType=try cloneType(c, value.returnType), noContext=value.noContext))
    case nt.Type.CompilerKnown:
        ret try makeNodeType(c, nt.Type.CompilerKnown(name=value.name, resolvedValue=value.resolvedValue))
    case nt.Type.Void:
        ret try makeNodeType(c, nt.Type.Void(x=value.x))
    ..
    throw "cannot clone type node"
..

cloneLiteral(c Checker*, source nt.Literal*) !nt.Literal*:
    if source == none:
        ret none
    ..
    local := nt.loadLiteralNode(source)
    id u64 = 0
    match local as value:
    case nt.Literal.None:
        id = try c.file.astNodes.push(nt.Literal.None().proto[nt.Node]())
    case nt.Literal.String:
        id = try c.file.astNodes.push(nt.Literal.String(value=value.value).proto[nt.Node]())
    case nt.Literal.Number:
        id = try c.file.astNodes.push(nt.Literal.Number(value=value.value).proto[nt.Node]())
    case nt.Literal.HexNumber:
        id = try c.file.astNodes.push(nt.Literal.HexNumber(value=value.value).proto[nt.Node]())
    case nt.Literal.Boolean:
        id = try c.file.astNodes.push(nt.Literal.Boolean(value=value.value).proto[nt.Node]())
    case nt.Literal.Char8:
        id = try c.file.astNodes.push(nt.Literal.Char8(value=value.value).proto[nt.Node]())
    case nt.Literal.Char32:
        id = try c.file.astNodes.push(nt.Literal.Char32(value=value.value).proto[nt.Node]())
    ..
    node := try c.file.astNodes.get(id)
    ret try node.implBorrow[nt.Literal]()
..

cloneExpression(c Checker*, source nt.Expr*) !nt.Expr*:
    if source == none:
        ret none
    ..
    match source as value:
    case nt.Expr.Empty:
        ret try makeNodeExpression(c, nt.Expr.Empty())
    case nt.Expr.Literal:
        ret try makeNodeExpression(c, nt.Expr.Literal(type=try cloneType(c, value.type), literal=try cloneLiteral(c, value.literal)))
    case nt.Expr.Named:
        ret try makeNodeExpression(c, nt.Expr.Named(type=try cloneType(c, value.type), name=value.name, decl=value.decl, category=value.category, sourcePos=value.sourcePos))
    case nt.Expr.MemberAccess:
        ret try makeNodeExpression(c, nt.Expr.MemberAccess(type=try cloneType(c, value.type), owner=try cloneExpression(c, value.owner), member=try cloneExpression(c, value.member), category=value.category, isProtoMethod=value.isProtoMethod))
    case nt.Expr.Subscript:
        ret try makeNodeExpression(c, nt.Expr.Subscript(type=try cloneType(c, value.type), owner=try cloneExpression(c, value.owner), index=try cloneExpression(c, value.index), category=value.category))
    case nt.Expr.Array:
        indices := nt.emptyIndexArray()
        for i := 0 to value.resolvedIndices.count():
            try indices.pushRight(ctx.alloc, try value.resolvedIndices.get(i))
        ..
        ret try makeNodeExpression(c, nt.Expr.Array(type=try cloneType(c, value.type), length=try cloneExpression(c, value.length), inferLength=value.inferLength, resolvedLength=value.resolvedLength, hasResolvedLength=value.hasResolvedLength, resolvedIndices=move indices))
    case nt.Expr.Embed:
        ret try makeNodeExpression(c, nt.Expr.Embed(path=value.path))
    case nt.Expr.CompilerKnown:
        ret try makeNodeExpression(c, nt.Expr.CompilerKnown(name=value.name, resolvedValue=value.resolvedValue))
    case nt.Expr.InlineLLVM:
        arguments := nt.emptyExpressionArray()
        for i := 0 to value.args.count():
            try arguments.pushRight(ctx.alloc, try cloneExpression(c, value.args.get(i)))
        ..
        ret try makeNodeExpression(c, nt.Expr.InlineLLVM(type=try cloneType(c, value.type), operation=value.operation, args=move arguments))
    case nt.Expr.VarDef:
        ret try makeNodeExpression(c, nt.Expr.VarDef(type=try cloneType(c, value.type), name=value.name, decl=value.decl, boundedCount=value.boundedCount, sourcePos=value.sourcePos))
    case nt.Expr.VarDefAssign:
        ret try makeNodeExpression(c, nt.Expr.VarDefAssign(type=try cloneType(c, value.type), name=value.name, assignment=try cloneExpression(c, value.assignment), decl=value.decl, sourcePos=value.sourcePos))
    case nt.Expr.VarDefAssignDestructure:
        ret try makeNodeExpression(c, nt.Expr.VarDefAssignDestructure(type=try cloneType(c, value.type), nameValue=value.nameValue, nameError=value.nameError, call=try cloneExpression(c, value.call), valueDecl=value.valueDecl, errorDecl=value.errorDecl))
    case nt.Expr.Sizeof:
        ret try makeNodeExpression(c, nt.Expr.Sizeof(type=try cloneType(c, value.type), operand=try cloneType(c, value.operand)))
    case nt.Expr.Unary:
        ret try makeNodeExpression(c, nt.Expr.Unary(type=try cloneType(c, value.type), op=value.op, operand=try cloneExpression(c, value.operand), category=value.category, floatingPoint=value.floatingPoint))
    case nt.Expr.Move:
        ret try makeNodeExpression(c, nt.Expr.Move(type=try cloneType(c, value.type), operand=try cloneExpression(c, value.operand)))
    case nt.Expr.Binary:
        ret try makeNodeExpression(c, nt.Expr.Binary(type=try cloneType(c, value.type), op=value.op, left=try cloneExpression(c, value.left), right=try cloneExpression(c, value.right), protoEquality=value.protoEquality, stringEquality=value.stringEquality, floatingPoint=value.floatingPoint, unsignedOperation=value.unsignedOperation))
    case nt.Expr.DirectCall:
        args := nt.emptyExpressionArray()
        typeArgs := nt.emptyTypeArray()
        for i := 0 to value.args.count():
            try args.pushRight(ctx.alloc, try cloneExpression(c, value.args.get(i)))
        ..
        for i := 0 to value.typeArgs.count():
            try typeArgs.pushRight(ctx.alloc, try cloneType(c, value.typeArgs.get(i)))
        ..
        ret try makeNodeExpression(c, nt.Expr.DirectCall(type=try cloneType(c, value.type), decl=value.decl, args=move args, typeArgs=move typeArgs, sourcePos=value.sourcePos, callKind=value.callKind))
    case nt.Expr.TemplatedDirectCall:
        args := nt.emptyExpressionArray()
        typeArgs := nt.emptyTypeArray()
        for i := 0 to value.args.count():
            try args.pushRight(ctx.alloc, try cloneExpression(c, value.args.get(i)))
        ..
        for i := 0 to value.typeArgs.count():
            try typeArgs.pushRight(ctx.alloc, try cloneType(c, value.typeArgs.get(i)))
        ..
        ret try makeNodeExpression(c, nt.Expr.TemplatedDirectCall(type=try cloneType(c, value.type), decl=value.decl, args=move args, typeArgs=move typeArgs, sourcePos=value.sourcePos, callKind=value.callKind))
    case nt.Expr.IndirectCall:
        args := nt.emptyExpressionArray()
        typeArgs := nt.emptyTypeArray()
        for i := 0 to value.args.count():
            try args.pushRight(ctx.alloc, try cloneExpression(c, value.args.get(i)))
        ..
        for i := 0 to value.typeArgs.count():
            try typeArgs.pushRight(ctx.alloc, try cloneType(c, value.typeArgs.get(i)))
        ..
        ret try makeNodeExpression(c, nt.Expr.IndirectCall(type=try cloneType(c, value.type), owner=try cloneExpression(c, value.owner), args=move args, typeArgs=move typeArgs, sourcePos=value.sourcePos, callKind=value.callKind, target=value.target))
    case nt.Expr.TemplatedIndirectCall:
        args := nt.emptyExpressionArray()
        typeArgs := nt.emptyTypeArray()
        for i := 0 to value.args.count():
            try args.pushRight(ctx.alloc, try cloneExpression(c, value.args.get(i)))
        ..
        for i := 0 to value.typeArgs.count():
            try typeArgs.pushRight(ctx.alloc, try cloneType(c, value.typeArgs.get(i)))
        ..
        ret try makeNodeExpression(c, nt.Expr.TemplatedIndirectCall(type=try cloneType(c, value.type), owner=try cloneExpression(c, value.owner), args=move args, typeArgs=move typeArgs, sourcePos=value.sourcePos, callKind=value.callKind, target=value.target))
    case nt.Expr.GenericApply:
        typeArgs := nt.emptyTypeArray()
        for i := 0 to value.typeArgs.count():
            try typeArgs.pushRight(ctx.alloc, try cloneType(c, value.typeArgs.get(i)))
        ..
        ret try makeNodeExpression(c, nt.Expr.GenericApply(type=try cloneType(c, value.type), owner=try cloneExpression(c, value.owner), typeArgs=move typeArgs))
    case nt.Expr.Try:
        ret try makeNodeExpression(c, nt.Expr.Try(type=try cloneType(c, value.type), call=try cloneExpression(c, value.call)))
    case nt.Expr.Assign:
        ret try makeNodeExpression(c, nt.Expr.Assign(type=try cloneType(c, value.type), assignee=try cloneExpression(c, value.assignee), expr=try cloneExpression(c, value.expr), sourcePos=value.sourcePos, resolvedFieldIndex=value.resolvedFieldIndex, hasResolvedFieldIndex=value.hasResolvedFieldIndex))
    case nt.Expr.Return:
        ret try makeNodeExpression(c, nt.Expr.Return(expr=try cloneExpression(c, value.expr), sourcePos=value.sourcePos))
    case nt.Expr.Throw:
        ret try makeNodeExpression(c, nt.Expr.Throw(expr=try cloneExpression(c, value.expr), sourcePos=value.sourcePos))
    ..
    throw "cannot clone expression node"
..

makeNodeExpression(c Checker*, value nt.Expr) !nt.Expr*:
    id := try c.file.astNodes.push(value.proto[nt.Node]())
    node := try c.file.astNodes.get(id)
    ret try node.implBorrow[nt.Expr]()
..

cloneCase(c Checker*, source nt.MatchCase*) !nt.MatchCase*:
    if source == none:
        ret none
    ..
    local nt.MatchCase
    unsafe:
        local = *source
    ..
    ret try makeNodeCase(c, nt.MatchCase(variant=try cloneName(c, local.variant), decl=local.decl, body=try cloneStatement(c, local.body)))
..

makeNodeCase(c Checker*, value nt.MatchCase) !nt.MatchCase*:
    id := try c.file.astNodes.push(value.proto[nt.Node]())
    node := try c.file.astNodes.get(id)
    ret try node.implBorrow[nt.MatchCase]()
..

cloneStatement(c Checker*, source nt.Stmt*) !nt.Stmt*:
    if source == none:
        ret none
    ..
    match source as value:
    case nt.Stmt.Body:
        statements := nt.emptyStatementArray()
        for i := 0 to value.statements.count():
            try statements.pushRight(ctx.alloc, try cloneStatement(c, value.statements.get(i)))
        ..
        ret try makeNodeStatement(c, nt.Stmt.Body(statements=move statements, scope=value.scope))
    case nt.Stmt.Expression:
        ret try makeNodeStatement(c, nt.Stmt.Expression(expr=try cloneExpression(c, value.expr)))
    case nt.Stmt.Break:
        ret try makeNodeStatement(c, nt.Stmt.Break())
    case nt.Stmt.Continue:
        ret try makeNodeStatement(c, nt.Stmt.Continue())
    case nt.Stmt.Defer:
        ret try makeNodeStatement(c, nt.Stmt.Defer(expr=try cloneExpression(c, value.expr), body=try cloneStatement(c, value.body)))
    case nt.Stmt.OnError:
        ret try makeNodeStatement(c, nt.Stmt.OnError(expr=try cloneExpression(c, value.expr), body=try cloneStatement(c, value.body)))
    case nt.Stmt.Unsafe:
        ret try makeNodeStatement(c, nt.Stmt.Unsafe(expr=try cloneExpression(c, value.expr), body=try cloneStatement(c, value.body)))
    case nt.Stmt.Bounded:
        predicates := nt.emptyExpressionArray()
        pointers := nt.emptyExpressionArray()
        extents := nt.emptyExpressionArray()
        for i := 0 to value.predicates.count():
            try predicates.pushRight(ctx.alloc, try cloneExpression(c, value.predicates.get(i)))
        ..
        for i := 0 to value.pointers.count():
            try pointers.pushRight(ctx.alloc, try cloneExpression(c, value.pointers.get(i)))
        ..
        for i := 0 to value.extents.count():
            try extents.pushRight(ctx.alloc, try cloneExpression(c, value.extents.get(i)))
        ..
        ret try makeNodeStatement(c, nt.Stmt.Bounded(predicates=move predicates, pointers=move pointers, extents=move extents, body=try cloneStatement(c, value.body)))
    case nt.Stmt.Match:
        cases := nt.emptyMatchCaseArray()
        for i := 0 to value.cases.count():
            try cases.pushRight(ctx.alloc, try cloneCase(c, value.cases.get(i)))
        ..
        ret try makeNodeStatement(c, nt.Stmt.Match(expression=try cloneExpression(c, value.expression), binding=value.binding, bindingDecl=value.bindingDecl, cases=move cases, elseBody=try cloneStatement(c, value.elseBody), pointerMode=value.pointerMode))
    case nt.Stmt.LLVM:
        ret try makeNodeStatement(c, nt.Stmt.LLVM(text=value.text))
    case nt.Stmt.If:
        ret try makeNodeStatement(c, nt.Stmt.If(condition=try cloneExpression(c, value.condition), body=try cloneStatement(c, value.body), next=try cloneStatement(c, value.next), sourcePos=value.sourcePos))
    case nt.Stmt.Elif:
        ret try makeNodeStatement(c, nt.Stmt.Elif(condition=try cloneExpression(c, value.condition), body=try cloneStatement(c, value.body), next=try cloneStatement(c, value.next), sourcePos=value.sourcePos))
    case nt.Stmt.Else:
        ret try makeNodeStatement(c, nt.Stmt.Else(body=try cloneStatement(c, value.body)))
    case nt.Stmt.Loop:
        ret try makeNodeStatement(c, nt.Stmt.Loop(condition=try cloneExpression(c, value.condition), body=try cloneStatement(c, value.body), sourcePos=value.sourcePos))
    case nt.Stmt.ForLoop:
        ret try makeNodeStatement(c, nt.Stmt.ForLoop(index=try cloneExpression(c, value.index), bound=try cloneExpression(c, value.bound), body=try cloneStatement(c, value.body), scope=value.scope))
    ..
    throw "cannot clone statement node"
..

makeNodeStatement(c Checker*, value nt.Stmt) !nt.Stmt*:
    id := try c.file.astNodes.push(value.proto[nt.Node]())
    node := try c.file.astNodes.get(id)
    ret try node.implBorrow[nt.Stmt]()
..

cloneHeader(c Checker*, source nt.Header*) !nt.Header*:
    if source == none:
        ret none
    ..
    fields := nt.emptyExpressionArray()
    for i := 0 to source.fields.count():
        try fields.pushRight(ctx.alloc, try cloneExpression(c, source.fields.get(i)))
    ..
    kind := source.kind
    match kind as headerKind:
    case nt.HeaderKind.Plain:
        kind = nt.HeaderKind.Plain()
    case nt.HeaderKind.Templated:
        args := nt.emptyTypeArray()
        for i := 0 to headerKind.typeArgs.count():
            try args.pushRight(ctx.alloc, try cloneType(c, headerKind.typeArgs.get(i)))
        ..
        kind = nt.HeaderKind.Templated(typeArgs=move args)
    ..
    id := try c.file.astNodes.push(nt.Header(decl=source.decl, scope=source.scope, name=source.name, fields=move fields, kind=kind).proto[nt.Node]())
    node := try c.file.astNodes.get(id)
    ret try node.implBorrow[nt.Header]()
..

primitiveTypeForName(name str) nt.PrimitiveType:
    if name == "ptr": ret nt.PrimitiveType.Pointer ..
    if name == "void": ret nt.PrimitiveType.Void ..
    if name == "bool": ret nt.PrimitiveType.Bool ..
    if name == "i8": ret nt.PrimitiveType.I8 ..
    if name == "i16": ret nt.PrimitiveType.I16 ..
    if name == "i32": ret nt.PrimitiveType.I32 ..
    if name == "i64": ret nt.PrimitiveType.I64 ..
    if name == "i128": ret nt.PrimitiveType.I128 ..
    if name == "u8": ret nt.PrimitiveType.U8 ..
    if name == "u16": ret nt.PrimitiveType.U16 ..
    if name == "u32": ret nt.PrimitiveType.U32 ..
    if name == "u64": ret nt.PrimitiveType.U64 ..
    if name == "u128": ret nt.PrimitiveType.U128 ..
    if name == "f16": ret nt.PrimitiveType.F16 ..
    if name == "f32": ret nt.PrimitiveType.F32 ..
    if name == "f64": ret nt.PrimitiveType.F64 ..
    if name == "f128": ret nt.PrimitiveType.F128 ..
    if name == "str": ret nt.PrimitiveType.String ..
    if name == "error": ret nt.PrimitiveType.Error ..
    if name == "slice": ret nt.PrimitiveType.Slice ..
    if name == "none": ret nt.PrimitiveType.None ..
    ret nt.PrimitiveType.Unresolved
..

makeSimpleType(c Checker*, name str) !nt.Type*:
    nameId := try c.file.astNodes.push(nt.Name.Simple(name=name).proto[nt.Node]())
    nameNode := try c.file.astNodes.get(nameId)
    namePtr := try nameNode.implBorrow[nt.Name]()
    ret try makeNodeType(c, nt.Type.Named(name=namePtr, decl=none, primitive=primitiveTypeForName(name)))
..

makePointerType(c Checker*, base nt.Type*) !nt.Type*:
    ret try makeNodeType(c, nt.Type.Pointer(toType=base))
..

makeSliceType(c Checker*, base nt.Type*) !nt.Type*:
    ret try makeNodeType(c, nt.Type.Slice(ofType=base))
..

simpleTypeName(t nt.Type*) str:
    if t == none:
        ret ""
    ..
    match t as value:
    case nt.Type.Named:
        if value.name == none:
            ret ""
        ..
        match value.name as name:
        case nt.Name.Simple:
            ret name.name
        else:
            ret ""
        ..
    else:
        ret ""
    ..
..

simpleTypeNameIs(type nt.Type*, name str) bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.Named:
        ret simpleTypeName(type) == name
    else:
        ret false
    ..
..

isStringValueType(type nt.Type*, depth u64) bool:
    if type == none || depth > 64:
        ret false
    ..
    match type as value:
    case nt.Type.Owned:
        ret isStringValueType(value.ofType, depth + 1)
    case nt.Type.Named:
        if value.primitive == nt.PrimitiveType.String:
            ret true
        ..
        if value.decl != none:
            match value.decl.kind as declaration:
            case dclr.DeclKind.Alias:
                ret isStringValueType(declaration.target, depth + 1)
            case dclr.DeclKind.Enum:
                ret isStringValueType(declaration.backing, depth + 1)
            else:
                ret false
            ..
        ..
        ret false
    else:
        ret false
    ..
..

canonicalTypeName(type nt.Type*, depth u64) str:
    if type == none || depth > 64:
        ret ""
    ..
    match type as value:
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as declaration:
            case dclr.DeclKind.Alias:
                ret canonicalTypeName(declaration.target, depth + 1)
            else:
                ret simpleTypeName(type)
            ..
        ..
        ret simpleTypeName(type)
    else:
        ret ""
    ..
..

typeShape(type nt.Type*) !str:
    if type == none:
        ret "<missing>"
    ..
    match type as value:
    case nt.Type.Named:
        name := try typeBaseName(type)
        if name == "":
            ret "named"
        ..
        if value.decl != none && value.decl.module != none:
            moduleName := try strgs.concat("@", value.decl.module.path)
            defer moduleName.free()
            ret try strgs.concat(name, moduleName)
        ..
        ret name
    case nt.Type.Pointer:
        ret try strgs.concat(try typeShape(value.toType), "*")
    case nt.Type.Slice:
        ret try strgs.concat(try typeShape(value.ofType), "[]")
    case nt.Type.Owned:
        ret try strgs.concat("$", try typeShape(value.ofType))
    case nt.Type.Throwing:
        ret try strgs.concat("!", try typeShape(value.ofType))
    case nt.Type.Templated:
        ret try typeBaseName(value.owner)
    case nt.Type.Function:
        ret "function"
    case nt.Type.Void:
        ret "void"
    case nt.Type.CompilerKnown:
        ret value.name
    ..
    ret "unknown"
..

stripOwnedType(type nt.Type*) nt.Type*:
    if type == none:
        ret none
    ..
    match type as value:
    case nt.Type.Owned:
        ret value.ofType
    else:
        ret type
    ..
..

isBuiltinType(name str) bool:
    if name == "void" || name == "bool" || name == "str" || name == "error" || name == "ptr" || name == "slice" || name == "none":
        ret true
    ..
    if name == "i8" || name == "i16" || name == "i32" || name == "i64" || name == "i128":
        ret true
    ..
    if name == "u8" || name == "u16" || name == "u32" || name == "u64" || name == "u128":
        ret true
    ..
    ret name == "f16" || name == "f32" || name == "f64" || name == "f128"
..

isTypeDecl(declaration dclr.Decl*) bool:
    kind := declaration.kind
    match kind as value:
    case dclr.DeclKind.Struct:
        ret true
    case dclr.DeclKind.Alias:
        ret true
    case dclr.DeclKind.Enum:
        ret true
    case dclr.DeclKind.Proto:
        ret true
    case dclr.DeclKind.Union:
        ret true
    case dclr.DeclKind.UnionVariant:
        ret true
    case dclr.DeclKind.TypeParameter:
        ret true
    else:
        ret false
    ..
..


resolveName(c Checker*, name str, scope dclr.Scope*) !dclr.Decl*:
    if scope != none:
        declaration, lookupErr := scope.getDeclFromName(name)
        if lookupErr.nok():
            # Some declaration scopes (notably scopes reconstructed for a
            # specialization) do not retain their module parent. Module level
            # declarations are still visible there, so consult the owning
            # module before reporting an unresolved local name.
            if c.module != none:
                moduleDeclaration, moduleErr := c.module.getDeclFromName(name)
                if moduleErr.ok():
                    ret moduleDeclaration
                ..
            ..
            if isBuiltinType(name) && c.coreModule != none:
                coreDeclaration, coreErr := c.coreModule.getDeclFromName(name)
                if coreErr.ok():
                    ret coreDeclaration
                ..
            ..
            throw try strgs.concat("name is not declared in scope: ", name)
        ..
        ret declaration
    ..
    declaration, lookupErr := c.module.getDeclFromName(name)
    if lookupErr.nok():
        if isBuiltinType(name) && c.coreModule != none:
            coreDeclaration, coreErr := c.coreModule.getDeclFromName(name)
            if coreErr.ok():
                ret coreDeclaration
            ..
        ..
        throw try strgs.concat("name is not declared in module: ", name)
    ..
    ret declaration
..

fileForScope(c Checker*, scope dclr.Scope*) !fctx.FileCtx*:
    if scope != none && scope.module != none:
        if c.module != none && scope.module.path == c.module.path:
            ret c.file
        ..
        ret try gl.files.get(scope.module.path)
    ..
    ret c.file
..

isImportedAlias(c Checker*, name str, scope dclr.Scope*) !bool:
    file := try fileForScope(c, scope)
    ret file.importAlias.contains(name)
..

checkVisibleInModule(c Checker*, declaration dclr.Decl*, accessingModule dclr.Module*) !void:
    sameModule := declaration.module == accessingModule
    if not sameModule && declaration.module != none && accessingModule != none:
        sameModule = strgs.compare(declaration.module.path, accessingModule.path)
    ..
    sameCoreModule := declaration.module == c.coreModule
    if not sameCoreModule && declaration.module != none && c.coreModule != none:
        sameCoreModule = strgs.compare(declaration.module.path, c.coreModule.path)
    ..
    if sameModule || sameCoreModule || declaration.isPublic:
        ret
    ..
    match declaration.kind as member:
    case dclr.DeclKind.Function:
        ownerEnd, ownerEndErr := strgs.findByte(member.name, 46)
        if ownerEndErr.ok():
            ownerName := try strgs.substring(member.name, 0, ownerEnd)
            defer ownerName.free()
            ownerDecl, ownerErr := declaration.module.getDeclFromName(ownerName)
            if ownerErr.ok() && ownerDecl.isPublic:
                match ownerDecl.kind as owner:
                case dclr.DeclKind.Struct:
                    ret
                case dclr.DeclKind.Proto:
                    ret
                else:
                    ownerDecl = ownerDecl
                ..
            ..
        ..
    else:
        declaration = declaration
    ..
    throw "cannot access a private declaration from another module"
..

checkVisible(c Checker*, declaration dclr.Decl*) !void:
    try checkVisibleInModule(c, declaration, c.module)
..

resolveCompositeName(c Checker*, name nt.Name.Composite*, scope dclr.Scope*) !dclr.Decl*:
    if name.names.count() == 0:
        throw "empty composite name"
    ..
    first := try name.names.get(0)
    file := try fileForScope(c, scope)
    imported := try isImportedAlias(c, first, scope)
    parent dclr.Decl* = none
    module dclr.Module* = none
    if imported:
        importPath, importErr := file.importAlias.get(first)
        if importErr.nok():
            throw "import alias is not registered"
        ..
        resolvedModule, moduleErr := dclr.getModuleFromPath(importPath)
        if moduleErr.nok():
            throw "imported module is not registered"
        ..
        module = resolvedModule
    else:
        parent = try resolveName(c, first, scope)
    ..

    for i := 1 to name.names.count():
        part := try name.names.get(i)
        if module != none:
            resolvedDeclaration, declarationErr := module.getDeclFromName(part)
            if declarationErr.nok():
                throw "imported declaration is not registered"
            ..
            parent = resolvedDeclaration
            accessingModule := c.module
            if scope != none:
                accessingModule = scope.module
            ..
            if module != accessingModule:
                try checkVisibleInModule(c, parent, accessingModule)
            ..
            module = none
        else:
            parent = try parent.access(part)
        ..
    ..
    if parent == none:
        throw "could not resolve composite name"
    ..
    ret parent
..

resolveNamedDecl(c Checker*, name nt.Name*, scope dclr.Scope*) !dclr.Decl*:
    match name as value:
    case nt.Name.Simple:
        ret try resolveName(c, value.name, scope)
    case nt.Name.Composite:
        ret try resolveCompositeName(c, value, scope)
    ..
    throw "invalid name node"
..

appendExpressionNameParts(expression nt.Expr*, names nt.NodeArray[str]*) !void:
    if expression == none:
        throw "generic type name is incomplete"
    ..
    match expression as value:
    case nt.Expr.Named:
        try names.pushRight(ctx.alloc, value.name)
    case nt.Expr.MemberAccess:
        try appendExpressionNameParts(value.owner, names)
        match value.member as name:
        case nt.Expr.Named:
            try names.pushRight(ctx.alloc, name.name)
        else:
            throw "generic type name is incomplete"
        ..
    case nt.Expr.Subscript:
        throw "generic argument is not a type: composite path contains a subscript"
    case nt.Expr.IndirectCall:
        throw "generic argument is not a type: composite path contains a call"
    case nt.Expr.TemplatedIndirectCall:
        throw "generic argument is not a type: composite path contains a generic call"
    case nt.Expr.Unary:
        throw "generic argument is not a type: composite path contains a unary expression"
    case nt.Expr.Move:
        throw "generic argument is not a type: composite path contains a move"
    case nt.Expr.Try:
        throw "generic argument is not a type: composite path contains a try expression"
    case nt.Expr.Binary:
        throw "generic argument is not a type: composite path contains a binary expression"
    case nt.Expr.GenericApply:
        throw "generic argument is not a type: composite path contains a generic application"
    else:
        throw "generic argument is not a type: composite path contains another expression"
    ..
..

expressionIsDottedName(expression nt.Expr*) bool:
    if expression == none:
        ret false
    ..
    match expression as value:
    case nt.Expr.Named:
        ret true
    case nt.Expr.MemberAccess:
        match value.member as name:
        case nt.Expr.Named:
            ret expressionIsDottedName(value.owner)
        else:
            ret false
        ..
    else:
        ret false
    ..
..

expressionIsCompositeDottedName(expression nt.Expr*) bool:
    if expression == none:
        ret false
    ..
    match expression as value:
    case nt.Expr.MemberAccess:
        ret expressionIsDottedName(value.owner)
    else:
        ret false
    ..
..

expressionFirstName(expression nt.Expr*) str:
    if expression == none:
        ret ""
    ..
    match expression as value:
    case nt.Expr.Named:
        ret value.name
    case nt.Expr.MemberAccess:
        ret expressionFirstName(value.owner)
    else:
        ret ""
    ..
..

expressionLooksLikeType(c Checker*, expression nt.Expr*, scope dclr.Scope*) !bool:
    if expression == none:
        ret false
    ..
    match expression as value:
    case nt.Expr.Named:
        if isBuiltinType(value.name):
            ret true
        ..
        ret isTypeDecl(try resolveName(c, value.name, scope))
    case nt.Expr.MemberAccess:
        if not expressionIsDottedName(expression):
            ret false
        ..
        names := nt.emptyStringArray()
        try appendExpressionNameParts(expression, addrof names)
        if names.count() < 2:
            ret false
        ..
        first := try names.get(0)
        if not (try isImportedAlias(c, first, scope)):
            firstDeclaration := try resolveName(c, first, scope)
            if not isNamespaceDeclaration(firstDeclaration):
                ret false
            ..
        ..
        id := try c.file.astNodes.push(nt.Name.Composite(names=move names).proto[nt.Node]())
        node := try c.file.astNodes.get(id)
        composite := try node.implBorrow[nt.Name]()
        match composite as compositeName:
        case nt.Name.Composite:
            ret isTypeDecl(try resolveCompositeName(c, compositeName, scope))
        else:
            ret false
        ..
    else:
        ret false
    ..
..

expressionAsType(c Checker*, expression nt.Expr*, scope dclr.Scope*) !nt.Type*:
    if expression == none:
        throw "generic argument is not a type: missing expression"
    ..
    match expression as value:
    case nt.Expr.Named:
        ret try makeSimpleType(c, value.name)
    case nt.Expr.MemberAccess:
        names := nt.emptyStringArray()
        try appendExpressionNameParts(expression, addrof names)
        id := try c.file.astNodes.push(nt.Name.Composite(names=move names).proto[nt.Node]())
        node := try c.file.astNodes.get(id)
        name := try node.implBorrow[nt.Name]()
        ret try makeNodeType(c, nt.Type.Named(name=name, decl=none, primitive=nt.PrimitiveType.Unresolved))
    case nt.Expr.Unary:
        if value.op == tkt.KwType.ASTERIX:
            ret try makePointerType(c, try expressionAsType(c, value.operand, scope))
        ..
        throw "generic argument is not a type: unsupported unary expression"
    case nt.Expr.GenericApply:
        ret try checkExpression(c, expression, scope)
    case nt.Expr.Subscript:
        _ := try checkExpression(c, value.owner, scope)
        declaration := callableDeclaration(value.owner)
        if declaration == none:
            throw "generic argument is not a type: subscript owner has no declaration"
        ..
        match declaration.kind as declarationKind:
        case dclr.DeclKind.Function:
            if declarationKind.typeParams.count() == 0:
                throw "generic argument is not a type: function is not generic"
            ..
        case dclr.DeclKind.Struct:
            if declarationKind.typeParams.count() == 0:
                throw "generic argument is not a type: struct is not generic"
            ..
        else:
            throw "generic argument is not a type: unsupported subscript owner"
        ..
        parameters := try genericParams(declaration)
        arguments := nt.emptyTypeArray()
        if not (try expressionLooksLikeType(c, value.index, scope)):
            throw "generic argument is not a type"
        ..
        try arguments.pushRight(ctx.alloc, try expressionAsType(c, value.index, scope))
        ret try instantiateGenericReference(c, declaration, arguments, scope, none)
    else:
        throw "generic argument is not a type: unsupported expression form"
    ..
..

genericReferenceFromSubscript(c Checker*, declaration dclr.Decl*, index nt.Expr*, scope dclr.Scope*) !nt.Type*:
    if declaration == none:
        throw "declaration does not support generic application"
    ..
    match declaration.kind as declarationKind:
    case dclr.DeclKind.Function:
        if declarationKind.typeParams.count() == 0:
            throw "declaration does not support generic application"
        ..
    case dclr.DeclKind.Struct:
        if declarationKind.typeParams.count() == 0:
            throw "declaration does not support generic application"
        ..
    else:
        throw "declaration does not support generic application"
    ..
    parameters := try genericParams(declaration)
    arguments := nt.emptyTypeArray()
    try arguments.pushRight(ctx.alloc, try expressionAsType(c, index, scope))
    ret try instantiateGenericReference(c, declaration, arguments, scope, none)
..

checkType(c Checker*, type nt.Type*, scope dclr.Scope*, allowThrow bool) !void:
    if type == none:
        throw "missing type"
    ..
    match type as value:
    case nt.Type.Named:
        if value.primitive == nt.PrimitiveType.Unresolved && value.name != none:
            match value.name as primitiveName:
            case nt.Name.Simple:
                value.primitive = primitiveTypeForName(primitiveName.name)
            else:
                value.primitive = nt.PrimitiveType.Unresolved
            ..
        ..
        if value.decl != none:
            if not isTypeDecl(value.decl):
                throw "name does not denote a type"
            ..
            match value.decl.kind as aliasKind:
            case dclr.DeclKind.Alias:
                try validateAliasChain(c, value.decl, scope, dclr.emptyDeclArray(), 0)
            else:
                ret
            ..
            ret
        ..
        match value.name as name:
        case nt.Name.Simple:
            if isBuiltinType(name.name):
                if name.name == "str" || name.name == "error" || name.name == "slice":
                    declaration := try coreTypeDeclaration(c, name.name)
                    if not isTypeDecl(declaration):
                        throw "core intrinsic name does not denote a type"
                    ..
                    value.decl = declaration
                elif c.coreModule != none:
                    declaration, lookupErr := c.coreModule.getDeclFromName(name.name)
                    if lookupErr.ok() && isTypeDecl(declaration):
                        value.decl = declaration
                    ..
                ..
                ret
            ..
        case nt.Name.Composite:
            if value.name == none:
                throw "type name is empty"
            ..
        ..
        declaration := try resolveNamedDecl(c, value.name, scope)
        if not isTypeDecl(declaration):
            throw "name does not denote a type"
        ..
        value.decl = declaration
        match declaration.kind as resolvedKind:
        case dclr.DeclKind.Alias:
            try validateAliasChain(c, declaration, scope, dclr.emptyDeclArray(), 0)
        else:
            ret
        ..
    case nt.Type.Pointer:
        try checkType(c, value.toType, scope, false)
        if isVoidType(value.toType):
            throw "void cannot be used as a pointer target"
        ..
    case nt.Type.Templated:
        try checkType(c, value.owner, scope, false)
        for i := 0 to value.args.count():
            try checkType(c, value.args.get(i), scope, false)
        ..
        ownerDecl := try typeDeclaration(c, value.owner)
        ownerKind := ownerDecl.kind
        match ownerKind as generic:
        case dclr.DeclKind.Struct:
            if generic.typeParams.count() != value.args.count():
                throw "generic type argument count does not match the declaration"
            ..
            if generic.typeParams.count() != 0:
                concreteArgs := nt.emptyTypeArray()
                allConcrete := true
                for i := 0 to value.args.count():
                    argument := try substituteType(c, value.args.get(i))
                    allConcrete = allConcrete && not (try containsUnboundTypeParameter(c, argument, 0))
                    try concreteArgs.pushRight(ctx.alloc, argument)
                ..
                if allConcrete:
                    concreteType := try makeNodeType(c, nt.Type.Templated(owner=value.owner, args=concreteArgs))
                    try enqueueSpecialization(c, ownerDecl, concreteArgs, concreteType, false)
                ..
            ..
        else:
            throw "type does not accept generic arguments"
        ..
    case nt.Type.Slice:
        try checkType(c, value.ofType, scope, false)
    case nt.Type.Owned:
        try checkType(c, value.ofType, scope, false)
    case nt.Type.Throwing:
        if not allowThrow:
            throw "throwing types are only valid as function return types"
        ..
        try checkType(c, value.ofType, scope, false)
    case nt.Type.Function:
        for i := 0 to value.args.count():
            argumentType := try value.args.get(i)
            try checkType(c, argumentType, scope, false)
            if isVoidType(argumentType) || isThrowingType(argumentType):
                throw "function arguments cannot have void or throwing types"
            ..
        ..
        try checkType(c, value.returnType, scope, true)
    case nt.Type.CompilerKnown:
        try resolveCompilerKnownTypes(c, type, 0)
    case nt.Type.Void:
        ret
    ..
..

resolveCompilerKnownTypes(c Checker*, type nt.Type*, depth u64) !void:
    if type == none:
        ret
    ..
    if depth > 64:
        throw "cyclic type expression"
    ..
    match type as value:
    case nt.Type.CompilerKnown:
        resolvedName := known.resolve(value.name)
        if resolvedName == "":
            throw "compiler-known type is unavailable for the current target"
        ..
        resolvedType := try makeSimpleType(c, resolvedName)
        nt.copyTypeNode(type, resolvedType)
    case nt.Type.Pointer:
        try resolveCompilerKnownTypes(c, value.toType, depth + 1)
    case nt.Type.Templated:
        try resolveCompilerKnownTypes(c, value.owner, depth + 1)
        for i := 0 to value.args.count():
            try resolveCompilerKnownTypes(c, value.args.get(i), depth + 1)
        ..
    case nt.Type.Slice:
        try resolveCompilerKnownTypes(c, value.ofType, depth + 1)
    case nt.Type.Owned:
        try resolveCompilerKnownTypes(c, value.ofType, depth + 1)
    case nt.Type.Throwing:
        try resolveCompilerKnownTypes(c, value.ofType, depth + 1)
    case nt.Type.Function:
        for i := 0 to value.args.count():
            try resolveCompilerKnownTypes(c, value.args.get(i), depth + 1)
        ..
        try resolveCompilerKnownTypes(c, value.returnType, depth + 1)
    else:
        ret
    ..
..

canonicalType(type nt.Type*, depth u64) !nt.Type*:
    if depth > 64:
        throw "cyclic type alias"
    ..
    if type == none:
        ret none
    ..
    match type as value:
    case nt.Type.Named:
        if value.decl != none:
            kind := value.decl.kind
            match kind as aliasKind:
            case dclr.DeclKind.Alias:
                ret try canonicalType(aliasKind.target, depth + 1)
            else:
                ret type
            ..
        ..
    else:
        ret type
    ..
    ret type
..

validateAliasType(c Checker*, type nt.Type*, scope dclr.Scope*, seen dclr.DeclArray, depth u64) !void:
    if type == none:
        throw "missing type"
    ..
    if depth > 64:
        throw "cyclic type alias"
    ..
    try resolveCompilerKnownTypes(c, type, 0)
    match type as value:
    case nt.Type.Named:
        if value.decl == none:
            if isBuiltinType(simpleTypeName(type)):
                try checkType(c, type, scope, false)
                ret
            ..
            value.decl = try resolveNamedDecl(c, value.name, scope)
        ..
        if not isTypeDecl(value.decl):
            throw "alias target does not denote a type"
        ..
        match value.decl.kind as declaration:
        case dclr.DeclKind.Alias:
            try validateAliasChain(c, value.decl, scope, seen, depth + 1)
        else:
            ret
        ..
    case nt.Type.Pointer:
        try validateAliasType(c, value.toType, scope, seen, depth + 1)
    case nt.Type.Slice:
        try validateAliasType(c, value.ofType, scope, seen, depth + 1)
    case nt.Type.Owned:
        try validateAliasType(c, value.ofType, scope, seen, depth + 1)
    case nt.Type.Throwing:
        try validateAliasType(c, value.ofType, scope, seen, depth + 1)
    case nt.Type.Function:
        for i := 0 to value.args.count():
            try validateAliasType(c, value.args.get(i), scope, seen, depth + 1)
        ..
        try validateAliasType(c, value.returnType, scope, seen, depth + 1)
    case nt.Type.Templated:
        try validateAliasType(c, value.owner, scope, seen, depth + 1)
        for i := 0 to value.args.count():
            try validateAliasType(c, value.args.get(i), scope, seen, depth + 1)
        ..
    else:
        ret
    ..
..

validateAliasChain(c Checker*, declaration dclr.Decl*, scope dclr.Scope*, seen dclr.DeclArray, depth u64) !void:
    if depth > 64:
        throw "cyclic type alias"
    ..
    for i := 0 to seen.count():
        if try seen.get(i) == declaration:
            throw "cyclic type alias"
        ..
    ..
    try seen.pushRight(ctx.alloc, declaration)
    match declaration.kind as aliasDeclaration:
    case dclr.DeclKind.Alias:
        target := aliasDeclaration.target
        if target == none:
            throw "type alias has no target type"
        ..
        try validateAliasType(c, target, scope, seen, depth + 1)
    else:
        ret
    ..
..

sameType(a nt.Type*, b nt.Type*, depth u64) !bool:
    if a == b:
        ret true
    ..
    if depth > 64:
        throw "cyclic type alias"
    ..
    left := try canonicalType(a, depth)
    right := try canonicalType(b, depth)
    if left == right:
        ret true
    ..
    if left == none || right == none:
        ret false
    ..
    match left as l:
    case nt.Type.Named:
        match right as r:
        case nt.Type.Named:
            if l.decl != none || r.decl != none:
                if l.decl == r.decl:
                    ret true
                ..
                leftName := simpleTypeName(left)
                rightName := simpleTypeName(right)
                if leftName == rightName && isBuiltinType(leftName):
                    ret true
                ..
                if l.decl != none && r.decl != none && l.decl.module != none && r.decl.module != none:
                    leftKind := l.decl.kind
                    rightKind := r.decl.kind
                    match leftKind as leftDeclaration:
                    case dclr.DeclKind.TypeParameter:
                        ret false
                    else:
                        match rightKind as rightDeclaration:
                        case dclr.DeclKind.TypeParameter:
                            ret false
                        else:
                            sameModule := strgs.compare(l.decl.module.path, r.decl.module.path)
                            leftBaseName := try typeBaseName(left)
                            rightBaseName := try typeBaseName(right)
                            sameName := leftBaseName == rightBaseName
                            ret sameModule && sameName
                        ..
                    ..
                ..
                ret false
            ..
            ret simpleTypeName(left) == simpleTypeName(right)
        else:
            ret false
        ..
    case nt.Type.Pointer:
        match right as r:
        case nt.Type.Pointer:
            ret try sameType(l.toType, r.toType, depth + 1)
        else:
            ret false
        ..
    case nt.Type.Slice:
        match right as r:
        case nt.Type.Slice:
            ret try sameType(l.ofType, r.ofType, depth + 1)
        else:
            ret false
        ..
    case nt.Type.Owned:
        match right as r:
        case nt.Type.Owned:
            ret try sameType(l.ofType, r.ofType, depth + 1)
        else:
            ret false
        ..
    case nt.Type.Throwing:
        match right as r:
        case nt.Type.Throwing:
            ret try sameType(l.ofType, r.ofType, depth + 1)
        else:
            ret false
        ..
    case nt.Type.Templated:
        match right as r:
        case nt.Type.Templated:
            if l.args.count() != r.args.count():
                ret false
            ..
            if not (try sameType(l.owner, r.owner, depth + 1)):
                ret false
            ..
            for i := 0 to l.args.count():
                if not (try sameType(l.args.get(i), r.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret true
        else:
            ret false
        ..
    case nt.Type.Function:
        match right as r:
        case nt.Type.Function:
            if l.noContext != r.noContext || l.args.count() != r.args.count():
                ret false
            ..
            if not (try sameType(l.returnType, r.returnType, depth + 1)):
                ret false
            ..
            for i := 0 to l.args.count():
                if not (try sameType(l.args.get(i), r.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret true
        else:
            ret false
        ..
    case nt.Type.CompilerKnown:
        match right as r:
        case nt.Type.CompilerKnown:
            ret l.name == r.name
        else:
            ret false
        ..
    case nt.Type.Void:
        match right as r:
        case nt.Type.Void:
            ret true
        else:
            ret false
        ..
    ..
    ret false
..

sameCallableType(a nt.Type*, b nt.Type*, depth u64) !bool:
    if try sameType(stripOwnedType(a), stripOwnedType(b), depth):
        ret true
    ..
    if depth > 64 || a == none || b == none:
        ret false
    ..
    left := try canonicalType(a, depth)
    right := try canonicalType(b, depth)
    if simpleTypeNameIs(left, "ptr") && isPointerType(right):
        ret true
    ..
    if simpleTypeNameIs(right, "ptr") && isPointerType(left):
        ret true
    ..
    match left as leftFunction:
    case nt.Type.Pointer:
        match right as rightPointer:
        case nt.Type.Pointer:
            ret try sameCallableType(leftFunction.toType, rightPointer.toType, depth + 1)
        else:
            ret false
        ..
    case nt.Type.Slice:
        match right as rightSlice:
        case nt.Type.Slice:
            ret try sameCallableType(leftFunction.ofType, rightSlice.ofType, depth + 1)
        else:
            ret false
        ..
    case nt.Type.Throwing:
        match right as rightThrowing:
        case nt.Type.Throwing:
            ret try sameCallableType(leftFunction.ofType, rightThrowing.ofType, depth + 1)
        else:
            ret false
        ..
    case nt.Type.Templated:
        match right as rightTemplated:
        case nt.Type.Templated:
            if leftFunction.args.count() != rightTemplated.args.count() || not (try sameType(leftFunction.owner, rightTemplated.owner, depth + 1)):
                ret false
            ..
            for i := 0 to leftFunction.args.count():
                if not (try sameCallableType(leftFunction.args.get(i), rightTemplated.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret true
        else:
            ret false
        ..
    case nt.Type.Function:
        match right as rightFunction:
        case nt.Type.Function:
            if leftFunction.noContext != rightFunction.noContext || leftFunction.args.count() != rightFunction.args.count():
                ret false
            ..
            for i := 0 to leftFunction.args.count():
                if not (try sameCallableType(leftFunction.args.get(i), rightFunction.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret try sameCallableType(leftFunction.returnType, rightFunction.returnType, depth + 1)
        else:
            ret false
        ..
    else:
        ret false
    ..
..

NumericInfo(width u64, integer bool, floating bool, unsigned bool)

numericInfoForName(name str) NumericInfo:
    if name == "i8" || name == "u8":
        ret NumericInfo(width=8, integer=true, floating=false, unsigned=name == "u8")
    elif name == "i16" || name == "u16":
        ret NumericInfo(width=16, integer=true, floating=false, unsigned=name == "u16")
    elif name == "i32" || name == "u32":
        ret NumericInfo(width=32, integer=true, floating=false, unsigned=name == "u32")
    elif name == "i64" || name == "u64":
        ret NumericInfo(width=64, integer=true, floating=false, unsigned=name == "u64")
    elif name == "i128" || name == "u128":
        ret NumericInfo(width=128, integer=true, floating=false, unsigned=name == "u128")
    elif name == "f16":
        ret NumericInfo(width=16, integer=false, floating=true, unsigned=false)
    elif name == "f32":
        ret NumericInfo(width=32, integer=false, floating=true, unsigned=false)
    elif name == "f64":
        ret NumericInfo(width=64, integer=false, floating=true, unsigned=false)
    elif name == "f128":
        ret NumericInfo(width=128, integer=false, floating=true, unsigned=false)
    ..
    ret NumericInfo(width=0, integer=false, floating=false, unsigned=false)
..

numericInfo(type nt.Type*, depth u64) NumericInfo:
    if type == none || depth > 64:
        ret NumericInfo(width=0, integer=false, floating=false, unsigned=false)
    ..
    match type as value:
    case nt.Type.CompilerKnown:
        ret NumericInfo(width=0, integer=false, floating=false, unsigned=false)
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as declaration:
            case dclr.DeclKind.Alias:
                ret numericInfo(declaration.target, depth + 1)
            case dclr.DeclKind.Enum:
                ret numericInfo(declaration.backing, depth + 1)
            case dclr.DeclKind.EnumVariant:
                ret numericInfo(declaration.type, depth + 1)
            else:
                ret NumericInfo(width=0, integer=false, floating=false, unsigned=false)
            ..
        ..
        match value.name as name:
        case nt.Name.Simple:
            ret numericInfoForName(name.name)
        else:
            ret NumericInfo(width=0, integer=false, floating=false, unsigned=false)
        ..
    else:
        ret NumericInfo(width=0, integer=false, floating=false, unsigned=false)
    ..
..

isIntegerType(type nt.Type*) bool:
    ret numericInfo(type, 0).integer
..

pub isFloatType(type nt.Type*) bool:
    ret numericInfo(type, 0).floating
..

pub isUnsignedType(type nt.Type*) bool:
    ret numericInfo(type, 0).unsigned
..

isNumericType(type nt.Type*) bool:
    ret numericInfo(type, 0).width != 0
..

applyNumericContext(c Checker*, expression nt.Expr*, expected nt.Type*, actual nt.Type*) !nt.Type*:
    if not isNumericType(expected) || expression == none:
        ret actual
    ..
    match expression as value:
    case nt.Expr.Literal:
        literal := nt.loadLiteralNode(value.literal)
        match literal as number:
        case nt.Literal.Number:
            value.type = expected
            ret expected
        else:
            ret actual
        ..
    else:
        ret actual
    ..
..

numericWidth(type nt.Type*) u64:
    ret numericInfo(type, 0).width
..

numericPromotion(c Checker*, left nt.Type*, right nt.Type*) !nt.Type*:
    leftInfo := numericInfo(left, 0)
    rightInfo := numericInfo(right, 0)
    if leftInfo.floating || rightInfo.floating:
        width := leftInfo.width
        if rightInfo.width > width:
            width = rightInfo.width
        ..
        if width <= 32:
            ret try makeSimpleType(c, "f32")
        ..
        if width <= 64:
            ret try makeSimpleType(c, "f64")
        ..
        ret try makeSimpleType(c, "f128")
    ..
    if rightInfo.width > leftInfo.width:
        ret right
    ..
    ret left
..

isBoolType(type nt.Type*) bool:
    ret simpleTypeNameIs(type, "bool")
..

isVoidType(type nt.Type*) bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.Void:
        ret true
    else:
        ret simpleTypeNameIs(type, "void")
    ..
..

isPointerType(type nt.Type*) bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.Pointer:
        ret true
    case nt.Type.Owned:
        ret isPointerType(value.ofType)
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as declaration:
            case dclr.DeclKind.Alias:
                ret isPointerType(declaration.target)
            else:
                ret simpleTypeNameIs(type, "ptr")
            ..
        ..
        ret simpleTypeNameIs(type, "ptr")
    else:
        ret simpleTypeNameIs(type, "ptr")
    ..
..

isFunctionType(type nt.Type*) bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.Function:
        ret true
    case nt.Type.Owned:
        ret isFunctionType(value.ofType)
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as declaration:
            case dclr.DeclKind.Alias:
                ret isFunctionType(declaration.target)
            else:
                ret false
            ..
        ..
        ret false
    else:
        ret false
    ..
..

isSliceType(type nt.Type*) bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.Slice:
        ret true
    case nt.Type.Owned:
        ret isSliceType(value.ofType)
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as declaration:
            case dclr.DeclKind.Alias:
                ret isSliceType(declaration.target)
            else:
                ret simpleTypeNameIs(type, "slice")
            ..
        ..
        ret simpleTypeNameIs(type, "slice")
    else:
        ret false
    ..
..

isCompilerKnownType(type nt.Type*) bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.CompilerKnown:
        ret true
    else:
        ret false
    ..
..

isCompatible(c Checker*, expected nt.Type*, actual nt.Type*) !bool:
    expectedValueType := stripOwnedType(expected)
    actualValueType := stripOwnedType(actual)
    if try sameCallableType(expectedValueType, actualValueType, 0):
        ret true
    ..
    # Unsafe code may explicitly reinterpret one typed object pointer as
    # another. Keep this permission lexical; raw/typed pointer compatibility
    # and all non-pointer checks retain their ordinary rules.
    if c.unsafeDepth != 0 && isPointerType(expectedValueType) && isPointerType(actualValueType):
        ret true
    ..
    if isSliceType(expectedValueType) && isSliceType(actualValueType):
        ret true
    ..
    if isCompilerKnownType(actualValueType):
        # The driver supplies the value and type of compiler-known constants;
        # use the surrounding declaration or parameter as the type context.
        ret true
    ..
    match actualValueType as ownedActual:
    case nt.Type.Owned:
        if isPointerType(expectedValueType) && (try sameType(expectedValueType, ownedActual.ofType, 0)):
            ret true
        ..
    else:
        
    ..
    if isNumericType(expectedValueType) && isNumericType(actualValueType):
        ret true
    ..
    if simpleTypeNameIs(expectedValueType, "ptr") && (isPointerType(actualValueType) || isFunctionType(actualValueType)):
        ret true
    ..
    if simpleTypeNameIs(actualValueType, "ptr") && (isPointerType(expectedValueType) || isFunctionType(expectedValueType)):
        ret true
    ..
    if simpleTypeNameIs(actualValueType, "none") && (isPointerType(expectedValueType) || isFunctionType(expectedValueType) || simpleTypeNameIs(expectedValueType, "ptr")):
        ret true
    ..
    ret false
..

coreTypeDeclaration(c Checker*, name str) !dclr.Decl*:
    if c.coreModule == none:
        throw "core module is missing from the parsed import graph"
    ..
    ret try c.coreModule.getDeclFromName(name)
..

typeDeclaration(c Checker*, type nt.Type*) !dclr.Decl*:
    if type == none:
        throw "expression has no type"
    ..
    if isBuiltinType(simpleTypeName(type)):
        try checkType(c, type, none, false)
    ..
    match type as value:
    case nt.Type.Named:
        if value.decl == none:
            throw "type name has not been linked"
        ..
        ret value.decl
    case nt.Type.Templated:
        ret try typeDeclaration(c, value.owner)
    case nt.Type.Pointer:
        ret try typeDeclaration(c, value.toType)
    case nt.Type.Slice:
        ret try coreTypeDeclaration(c, "slice")
    case nt.Type.Owned:
        ret try typeDeclaration(c, value.ofType)
    case nt.Type.Throwing:
        ret try typeDeclaration(c, value.ofType)
    else:
        throw "type has no declaration"
    ..
    throw "type has no declaration"
..

boundType(c Checker*, parameter dclr.Decl*) !nt.Type*:
    for i := 0 to c.bindingParams.count():
        boundParameter := try c.bindingParams.get(i)
        if boundParameter == parameter:
            ret try c.bindingTypes.get(i)
        ..
    ..
    ret none
..

boundTypeByName(c Checker*, name str) !nt.Type*:
    i := c.bindingParams.count()
    loop i > 0:
        i = i - 1
        parameter := try c.bindingParams.get(i)
        match parameter.kind as kind:
        case dclr.DeclKind.TypeParameter:
            if kind.name == name:
                ret try c.bindingTypes.get(i)
            ..
        else:
            parameter = parameter
        ..
    ..
    ret none
..

substituteType(c Checker*, type nt.Type*) !nt.Type*:
    if type == none:
        ret none
    ..
    match type as value:
    case nt.Type.Named:
        if value.decl != none:
            kind := value.decl.kind
            match kind as parameter:
            case dclr.DeclKind.TypeParameter:
                replacement := try boundType(c, value.decl)
                if replacement != none:
                    ret replacement
                ..
            else:
                ret type
            ..
        else:
            match value.name as name:
            case nt.Name.Simple:
                replacement := try boundTypeByName(c, name.name)
                if replacement != none:
                    ret replacement
                ..
            else:
                
            ..
        ..
        ret type
    case nt.Type.Pointer:
        target := try substituteType(c, value.toType)
        if target == value.toType:
            ret type
        ..
        ret try makePointerType(c, target)
    case nt.Type.Slice:
        element := try substituteType(c, value.ofType)
        if element == value.ofType:
            ret type
        ..
        ret try makeSliceType(c, element)
    case nt.Type.Owned:
        element := try substituteType(c, value.ofType)
        if element == value.ofType:
            ret type
        ..
        ret try makeNodeType(c, nt.Type.Owned(ofType=element))
    case nt.Type.Throwing:
        element := try substituteType(c, value.ofType)
        if element == value.ofType:
            ret type
        ..
        ret try makeNodeType(c, nt.Type.Throwing(ofType=element))
    case nt.Type.Templated:
        owner := try substituteType(c, value.owner)
        args := nt.emptyTypeArray()
        changed := owner != value.owner
        for i := 0 to value.args.count():
            oldArg := try value.args.get(i)
            newArg := try substituteType(c, oldArg)
            changed = changed || newArg != oldArg
            try args.pushRight(ctx.alloc, newArg)
        ..
        if not changed:
            ret type
        ..
        ret try makeNodeType(c, nt.Type.Templated(owner=owner, args=move args))
    case nt.Type.Function:
        args := nt.emptyTypeArray()
        changed := false
        for i := 0 to value.args.count():
            oldArg := try value.args.get(i)
            newArg := try substituteType(c, oldArg)
            changed = changed || newArg != oldArg
            try args.pushRight(ctx.alloc, newArg)
        ..
        result := try substituteType(c, value.returnType)
        changed = changed || result != value.returnType
        if not changed:
            ret type
        ..
        ret try makeNodeType(c, nt.Type.Function(args=move args, returnType=result, noContext=value.noContext))
    else:
        ret type
    ..
..

pushTypeBinding(c Checker*, parameter dclr.Decl*, actual nt.Type*) !void:
    existing := try boundType(c, parameter)
    if existing != none:
        if not (try sameType(existing, actual, 0)):
            throw "generic type parameter has conflicting inferred types"
        ..
        ret
    ..
    try c.bindingParams.pushRight(ctx.alloc, parameter)
    try c.bindingTypes.pushRight(ctx.alloc, actual)
..

pushLocalTypeBinding(c Checker*, declaration dclr.Decl*, actual nt.Type*) !void:
    existing := try boundType(c, declaration)
    if existing != none:
        if not (try sameType(existing, actual, 0)):
            throw "local declaration has inconsistent inferred types"
        ..
        ret
    ..
    try c.bindingParams.pushRight(ctx.alloc, declaration)
    try c.bindingTypes.pushRight(ctx.alloc, actual)
..

bindTypePattern(c Checker*, pattern nt.Type*, actual nt.Type*, depth u64) !void:
    if pattern == none || actual == none:
        ret
    ..
    if depth > 64:
        throw "generic type inference is recursively nested too deeply"
    ..
    match pattern as formal:
    case nt.Type.Named:
        if formal.decl != none:
            formalKind := formal.decl.kind
            match formalKind as parameter:
            case dclr.DeclKind.TypeParameter:
                try pushTypeBinding(c, formal.decl, actual)
                ret
            else:
                ret
            ..
        else:
            match formal.name as simple:
            case nt.Name.Simple:
                parameter, parameterErr := c.module.getDeclFromName(simple.name)
                if parameterErr.ok():
                    match parameter.kind as parameterKind:
                    case dclr.DeclKind.TypeParameter:
                        try pushTypeBinding(c, parameter, actual)
                    else:
                        parameter = parameter
                    ..
                ..
            else:
                
            ..
        ..
    case nt.Type.Pointer:
        match actual as concrete:
        case nt.Type.Pointer:
            try bindTypePattern(c, formal.toType, concrete.toType, depth + 1)
        else:
            ret
        ..
    case nt.Type.Slice:
        match actual as concrete:
        case nt.Type.Slice:
            try bindTypePattern(c, formal.ofType, concrete.ofType, depth + 1)
        else:
            ret
        ..
    case nt.Type.Owned:
        match actual as concrete:
        case nt.Type.Owned:
            try bindTypePattern(c, formal.ofType, concrete.ofType, depth + 1)
        else:
            try bindTypePattern(c, formal.ofType, actual, depth + 1)
        ..
    case nt.Type.Throwing:
        match actual as concrete:
        case nt.Type.Throwing:
            try bindTypePattern(c, formal.ofType, concrete.ofType, depth + 1)
        else:
            ret
        ..
    case nt.Type.Templated:
        match actual as concrete:
        case nt.Type.Templated:
            if formal.args.count() != concrete.args.count():
                ret
            ..
            try bindTypePattern(c, formal.owner, concrete.owner, depth + 1)
            for i := 0 to formal.args.count():
                try bindTypePattern(c, formal.args.get(i), concrete.args.get(i), depth + 1)
            ..
        else:
            ret
        ..
    case nt.Type.Function:
        match actual as concrete:
        case nt.Type.Function:
            if formal.args.count() != concrete.args.count():
                ret
            ..
            for i := 0 to formal.args.count():
                try bindTypePattern(c, formal.args.get(i), concrete.args.get(i), depth + 1)
            ..
            try bindTypePattern(c, formal.returnType, concrete.returnType, depth + 1)
        else:
            ret
        ..
    else:
        ret
    ..
..

enqueueSpecialization(c Checker*, template dclr.Decl*, typeArgs nt.NodeArray[nt.Type*], concreteType nt.Type*, isFunction bool) !void:
    provider := try gl.files.get(template.module.path)
    for i := 0 to provider.specializations.count():
        prior := try provider.specializations.get(i)
        if prior.template != template || prior.isFunction != isFunction || prior.typeArgs.count() != typeArgs.count():
            continue
        ..
        matches := true
        for j := 0 to typeArgs.count():
            if not (try sameType(prior.typeArgs.get(j), typeArgs.get(j), 0)):
                matches = false
                break
            ..
        ..
        if matches:
            ret
        ..
    ..
    if c.specializations.count() >= MAX_SPECIALIZATIONS:
        throw "generic specialization did not reach a fixed point after 10000 concrete instances"
    ..
    parameters := dclr.emptyDeclArray()
    match template.kind as templateKind:
    case dclr.DeclKind.Struct:
        for parameterIndex := 0 to templateKind.typeParams.count():
            try parameters.pushRight(ctx.alloc, try templateKind.typeParams.get(parameterIndex))
        ..
    case dclr.DeclKind.Function:
        if template.methodOwnerType != none:
            match template.methodOwnerType as ownerType:
            case nt.Type.Templated:
                match ownerType.owner as ownerName:
                case nt.Type.Named:
                    if ownerName.decl != none:
                        match ownerName.decl.kind as ownerKind:
                        case dclr.DeclKind.Struct:
                            for ownerParameterIndex := 0 to ownerKind.typeParams.count():
                                try parameters.pushRight(ctx.alloc, try ownerKind.typeParams.get(ownerParameterIndex))
                            ..
                        else:
                            parameters = parameters
                        ..
                    ..
                else:
                    parameters = parameters
                ..
            else:
                parameters = parameters
            ..
        ..
        for parameterIndex := 0 to templateKind.typeParams.count():
            try parameters.pushRight(ctx.alloc, try templateKind.typeParams.get(parameterIndex))
        ..
    else:
        parameters = parameters
    ..
    nodeId := try provider.astNodes.push(nt.Specialization(
        template=template,
        typeArgs=typeArgs,
        typeParams=parameters,
        concreteType=concreteType,
        concreteHeader=none,
        concreteBody=none,
        isFunction=isFunction,
        state=0,
    ).proto[nt.Node]())
    node := try provider.astNodes.get(nodeId)
    specialization := try node.implBorrow[nt.Specialization]()
    try provider.specializations.pushRight(ctx.alloc, specialization)
    try c.specializations.pushRight(ctx.alloc, specialization)
..

containsUnboundTypeParameter(c Checker*, type nt.Type*, depth u64) !bool:
    if type == none:
        ret false
    ..
    if depth > 64:
        throw "type structure is recursively nested too deeply"
    ..
    match type as value:
    case nt.Type.Named:
        if value.decl == none:
            match value.name as simpleName:
            case nt.Name.Simple:
                for i := 0 to c.bindingParams.count():
                    parameter := try c.bindingParams.get(i)
                    match parameter.kind as parameterKind:
                    case dclr.DeclKind.TypeParameter:
                        if parameterKind.name == simpleName.name:
                            bound := try c.bindingTypes.get(i)
                            if bound == none:
                                ret true
                            ..
                            match bound as boundValue:
                            case nt.Type.Named:
                                if boundValue.decl == none:
                                    match boundValue.name as boundName:
                                    case nt.Name.Simple:
                                        if boundName.name == simpleName.name:
                                            ret true
                                        ..
                                    else:
                                        ret try containsUnboundTypeParameter(c, bound, depth + 1)
                                    ..
                                ..
                            else:
                                ret try containsUnboundTypeParameter(c, bound, depth + 1)
                            ..
                            ret try containsUnboundTypeParameter(c, bound, depth + 1)
                        ..
                    else:
                        continue
                    ..
                ..
            else:
                ret false
            ..
            ret false
        ..
        kind := value.decl.kind
        match kind as parameter:
        case dclr.DeclKind.TypeParameter:
            bound := try boundType(c, value.decl)
            if bound == none:
                ret true
            ..
            match bound as boundTypeValue:
            case nt.Type.Named:
                if boundTypeValue.decl == value.decl:
                    ret true
                ..
            else:
                ret try containsUnboundTypeParameter(c, bound, depth + 1)
            ..
            ret try containsUnboundTypeParameter(c, bound, depth + 1)
        else:
            ret false
        ..
    case nt.Type.Pointer:
        ret try containsUnboundTypeParameter(c, value.toType, depth + 1)
    case nt.Type.Slice:
        ret try containsUnboundTypeParameter(c, value.ofType, depth + 1)
    case nt.Type.Owned:
        ret try containsUnboundTypeParameter(c, value.ofType, depth + 1)
    case nt.Type.Throwing:
        ret try containsUnboundTypeParameter(c, value.ofType, depth + 1)
    case nt.Type.Templated:
        if try containsUnboundTypeParameter(c, value.owner, depth + 1):
            ret true
        ..
        for i := 0 to value.args.count():
            if try containsUnboundTypeParameter(c, value.args.get(i), depth + 1):
                ret true
            ..
        ..
        ret false
    case nt.Type.Function:
        for i := 0 to value.args.count():
            if try containsUnboundTypeParameter(c, value.args.get(i), depth + 1):
                ret true
            ..
        ..
        ret try containsUnboundTypeParameter(c, value.returnType, depth + 1)
    else:
        ret false
    ..
..

resolveImportedMember(c Checker*, aliasName str, memberName str, scope dclr.Scope*) !dclr.Decl*:
    file := try fileForScope(c, scope)
    importPath, importErr := file.importAlias.get(aliasName)
    if importErr.nok():
        throw "import alias is not registered"
    ..
    importedModule, moduleErr := dclr.getModuleFromPath(importPath)
    if moduleErr.nok():
        throw "imported module is not registered"
    ..
    declaration, declarationErr := importedModule.getDeclFromName(memberName)
    if declarationErr.nok():
        if importedModule.decls.count() == 0:
            throw "imported module has no parsed declarations"
        ..
        throw "imported module is missing the requested declaration"
    ..
    accessingModule := c.module
    if scope != none:
        accessingModule = scope.module
    ..
    try checkVisibleInModule(c, declaration, accessingModule)
    ret declaration
..

typeBaseName(type nt.Type*) !str:
    if type == none:
        ret ""
    ..
    match type as value:
    case nt.Type.Named:
        if value.name == none:
            ret ""
        ..
        match value.name as name:
        case nt.Name.Simple:
            ret name.name
        case nt.Name.Composite:
            if name.names.count() == 0:
                ret ""
            ..
            ret try name.names.get(name.names.count() - 1)
        ..
    case nt.Type.Templated:
        ret try typeBaseName(value.owner)
    case nt.Type.Pointer:
        ret try typeBaseName(value.toType)
    case nt.Type.Owned:
        ret try typeBaseName(value.ofType)
    case nt.Type.Throwing:
        ret try typeBaseName(value.ofType)
    case nt.Type.Slice:
        ret "slice"
    else:
        ret ""
    ..
    ret ""
..

resolveTypeMember(c Checker*, owner dclr.Decl*, ownerType nt.Type*, name str) !dclr.Decl*:
    kind := owner.kind
    match kind as value:
    case dclr.DeclKind.Struct:
        for i := 0 to value.fields.count():
            field := try value.fields.get(i)
            fieldKind := field.kind
            match fieldKind as member:
            case dclr.DeclKind.Field:
                if member.name == name:
                    ret field
                ..
            else:
                continue
            ..
        ..
        baseName := try typeBaseName(ownerType)
        qualified := try strgs.concat(baseName, ".")
        defer qualified.free()
        methodName := try strgs.concat(qualified, name)
        defer methodName.free()
        methodDecl, methodErr := owner.module.getDeclFromName(methodName)
        if methodErr.nok():
            throw "method declaration was not found"
        ..
        try checkVisible(c, methodDecl)
        ret methodDecl
    case dclr.DeclKind.Union:
        ret try owner.access(name)
    case dclr.DeclKind.UnionVariant:
        ret try owner.access(name)
    case dclr.DeclKind.Enum:
        ret try owner.access(name)
    case dclr.DeclKind.Proto:
        declaration, lookupErr := owner.access(name)
        if lookupErr.ok():
            ret declaration
        ..
        baseName := try typeBaseName(ownerType)
        qualified := try strgs.concat(baseName, ".")
        defer qualified.free()
        methodName := try strgs.concat(qualified, name)
        defer methodName.free()
        methodDecl, methodErr := owner.module.getDeclFromName(methodName)
        if methodErr.nok():
            throw try strgs.concat("prototype method declaration was not found: ", methodName)
        ..
        try checkVisible(c, methodDecl)
        ret methodDecl
    case dclr.DeclKind.Alias:
        aliasType := try typeOfDecl(c, owner, none)
        aliasDecl := try typeDeclaration(c, aliasType)
        ret try resolveTypeMember(c, aliasDecl, aliasType, name)
    else:
        throw "type has no accessible members"
    ..
..

resolveBuiltinTypeMember(c Checker*, ownerType nt.Type*, name str) !dclr.Decl*:
    baseName := try typeBaseName(ownerType)
    qualified := try strgs.concat(baseName, ".")
    defer qualified.free()
    methodName := try strgs.concat(qualified, name)
    defer methodName.free()

    declaration, lookupErr := c.module.getDeclFromName(methodName)
    if lookupErr.ok():
        ret declaration
    ..
    if c.coreModule != none && c.coreModule != c.module:
        coreDeclaration, coreLookupErr := c.coreModule.getDeclFromName(methodName)
        if coreLookupErr.ok():
            ret coreDeclaration
        ..
    ..
    throw "method is not declared for the built-in type"
..

isNamespaceDeclaration(declaration dclr.Decl*) bool:
    if declaration == none:
        ret false
    ..
    match declaration.kind as kind:
    case dclr.DeclKind.Module:
        ret true
    case dclr.DeclKind.Union:
        ret true
    case dclr.DeclKind.Enum:
        ret true
    case dclr.DeclKind.Proto:
        ret true
    else:
        ret false
    ..
..

declarationValueType(c Checker*, declaration dclr.Decl*, scope dclr.Scope*) !nt.Type*:
    match declaration.kind as kind:
    case dclr.DeclKind.Struct:
        ret declaration.declType
    case dclr.DeclKind.Union:
        ret declaration.declType
    case dclr.DeclKind.Enum:
        ret declaration.declType
    case dclr.DeclKind.Proto:
        ret declaration.declType
    else:
        ret try typeOfDecl(c, declaration, scope)
    ..
..

bindMemberOwnerType(c Checker*, type nt.Type*) !void:
    if type == none:
        ret
    ..
    match try canonicalType(type, 0) as value:
    case nt.Type.Pointer:
        try bindMemberOwnerType(c, value.toType)
    case nt.Type.Owned:
        try bindMemberOwnerType(c, value.ofType)
    case nt.Type.Templated:
        declaration := try typeDeclaration(c, value.owner)
        match declaration.kind as kind:
        case dclr.DeclKind.Struct:
            if kind.typeParams.count() != value.args.count():
                throw "generic type argument count does not match the declaration"
            ..
            for i := 0 to kind.typeParams.count():
                try pushTypeBinding(c, try kind.typeParams.get(i), try value.args.get(i))
            ..
        else:
            ret
        ..
    else:
        ret
    ..
..

checkExpression(c Checker*, expression nt.Expr*, scope dclr.Scope*) !nt.Type*:
    if expression == none:
        throw "missing expression"
    ..
    match expression as value:
    case nt.Expr.Empty:
        ret try makeNodeType(c, nt.Type.Void(x=0))
    case nt.Expr.Literal:
        match value.literal as literal:
        case nt.Literal.Number:
            value.type = try makeSimpleType(c, "i64")
        case nt.Literal.HexNumber:
            value.type = try makeSimpleType(c, "u64")
        case nt.Literal.String:
            value.type = try makeSimpleType(c, "str")
        case nt.Literal.Boolean:
            value.type = try makeSimpleType(c, "bool")
        case nt.Literal.Char8:
            value.type = try makeSimpleType(c, "u8")
        case nt.Literal.Char32:
            value.type = try makeSimpleType(c, "u32")
        case nt.Literal.None:
            value.type = try makeSimpleType(c, "none")
        ..
        ret value.type
    case nt.Expr.Named:
        declaration := try resolveName(c, value.name, scope)
        value.decl = declaration
        value.type = try typeOfDecl(c, declaration, scope)
        match declaration.kind as namedKind:
        case dclr.DeclKind.Variable:
            value.category = nt.ValueCategory.Place
        case dclr.DeclKind.Argument:
            value.category = nt.ValueCategory.Place
        else:
            value.category = nt.ValueCategory.Value
        ..
        ret value.type
    case nt.Expr.MemberAccess:
        memberName str = ""
        match value.member as member:
        case nt.Expr.Named:
            memberName = member.name
        else:
            throw "member access requires a name"
        ..
        declaration dclr.Decl* = none
        match value.owner as owner:
        case nt.Expr.Named:
            if try isImportedAlias(c, owner.name, scope):
                declaration = try resolveImportedMember(c, owner.name, memberName, scope)
            ..
        else:
            declaration = none
        ..
        if declaration == none && expressionIsCompositeDottedName(value.owner):
            firstOwnerName := expressionFirstName(value.owner)
            if try isImportedAlias(c, firstOwnerName, scope):
                ownerNames := nt.emptyStringArray()
                try appendExpressionNameParts(value.owner, addrof ownerNames)
                ownerName := nt.Name.Composite(names=move ownerNames)
                ownerDeclaration := try resolveNamedDecl(c, addrof ownerName, scope)
                if isNamespaceDeclaration(ownerDeclaration):
                    declaration = try ownerDeclaration.access(memberName)
                ..
            ..
        ..
        ownerType nt.Type* = none
        if declaration == none:
            ownerType = try checkExpression(c, value.owner, scope)
            ownerDecl, ownerErr := typeDeclaration(c, ownerType)
            if ownerErr.ok():
                declaration = try resolveTypeMember(c, ownerDecl, ownerType, memberName)
            elif isBuiltinType(try typeBaseName(ownerType)):
                declaration = try resolveBuiltinTypeMember(c, ownerType, memberName)
            else:
                throw ownerErr
            ..
        ..
        bindingCount := c.bindingParams.count()
        defer restoreBindingCount(c, bindingCount)
        if ownerType != none:
            try bindMemberOwnerType(c, ownerType)
        ..
        memberType := try substituteType(c, try declarationValueType(c, declaration, scope))
        match value.member as memberNode:
        case nt.Expr.Named:
            memberNode.decl = declaration
            memberNode.type = memberType
        else:
            throw "member access requires a name"
        ..
        value.type = memberType
        value.isProtoMethod = false
        if ownerType != none:
            ownerDeclaration, ownerError := typeDeclaration(c, ownerType)
            if ownerError.ok():
                match ownerDeclaration.kind as protoKind:
                case dclr.DeclKind.Proto:
                    for i := 0 to protoKind.methods.count():
                        required := try protoKind.methods.get(i)
                        if required == declaration:
                            value.isProtoMethod = true
                            break
                        ..
                    ..
                else:
                    ownerDeclaration = ownerDeclaration
                ..
            ..
        ..
        value.category = nt.ValueCategory.Value
        match declaration.kind as memberKind:
        case dclr.DeclKind.Field:
            if ownerType != none:
                match ownerType as ownerKind:
                case nt.Type.Pointer:
                    value.category = nt.ValueCategory.Place
                else:
                    if try isAssignableExpr(value.owner):
                        value.category = nt.ValueCategory.Place
                    ..
                ..
            ..
        case dclr.DeclKind.Variable:
            value.category = nt.ValueCategory.Place
        else:
            value.category = nt.ValueCategory.Value
        ..
        ret value.type
    case nt.Expr.Subscript:
        ownerType := try checkExpression(c, value.owner, scope)
        genericDeclaration := callableDeclaration(value.owner)
        if genericDeclaration != none:
            hasGenericParams := false
            match genericDeclaration.kind as declarationKind:
            case dclr.DeclKind.Function:
                hasGenericParams = declarationKind.typeParams.count() != 0
            case dclr.DeclKind.Struct:
                hasGenericParams = declarationKind.typeParams.count() != 0
            else:
                hasGenericParams = false
            ..
            if hasGenericParams && (try expressionLooksLikeType(c, value.index, scope)):
                ret try genericReferenceFromSubscript(c, genericDeclaration, value.index, scope)
            ..
        ..
        indexType := try checkExpression(c, value.index, scope)
        if not isIntegerType(indexType):
            throw "subscript index must be an integer"
        ..
        resolvedOwnerType := try canonicalType(ownerType, 0)
        match resolvedOwnerType as owner:
        case nt.Type.Pointer:
            value.type = owner.toType
        case nt.Type.Slice:
            value.type = owner.ofType
        case nt.Type.Owned:
            match owner.ofType as owned:
            case nt.Type.Pointer:
                value.type = owned.toType
            case nt.Type.Slice:
                value.type = owned.ofType
            else:
                throw "subscript requires a pointer or slice"
            ..
        else:
            throw "subscript requires a pointer or slice"
        ..
        value.category = nt.ValueCategory.Place
        ret value.type
    case nt.Expr.Array:
        try checkType(c, value.type, scope, false)
        if isVoidType(value.type) || isThrowingType(value.type):
            throw "array elements cannot have void or throwing types"
        ..
        if not value.inferLength && value.length != none:
            lengthType := try checkExpression(c, value.length, scope)
            if not isIntegerType(lengthType):
                throw "array length must be an integer"
            ..
        ..
        ret try makeSliceType(c, try substituteType(c, value.type))
    case nt.Expr.Embed:
        valueType := try makeSimpleType(c, "str")
        ret valueType
    case nt.Expr.CompilerKnown:
        if value.name == "ERROR_TRACE_SLOTS":
            value.resolvedValue = "1024"
        else:
            throw try strgs.concat("unknown compiler-known constant: ", value.name)
        ..
        valueType := try makeNodeType(c, nt.Type.CompilerKnown(name=value.name, resolvedValue=value.resolvedValue))
        ret valueType
    case nt.Expr.InlineLLVM:
        try checkType(c, value.type, scope, false)
        for i := 0 to value.args.count():
            _ := try checkExpression(c, value.args.get(i), scope)
        ..
        try checkInlineLLVMOperation(value.operation, value.args.count())
        if isThrowingType(value.type):
            throw "inline LLVM result cannot have a throwing type"
        ..
        ret try substituteType(c, value.type)
    case nt.Expr.VarDef:
        if value.type == none:
            throw "variable declaration requires an explicit type or initializer"
        ..
        try checkType(c, value.type, scope, false)
        if isVoidType(value.type) || isThrowingType(value.type):
            throw try strgs.concat("variables cannot have void or throwing types: ", value.name)
        ..
        if value.decl != none:
            resolvedType := try substituteType(c, value.type)
            value.decl.declType = resolvedType
            value.decl.semanticState = 2
            value.type = resolvedType
        ..
        ret try substituteType(c, value.type)
    case nt.Expr.VarDefAssign:
        actual := try checkExpression(c, value.assignment, scope)
        if c.checkingSpecialization:
            actual = try substituteType(c, actual)
        ..
        resultType := value.type
        if value.type == none:
            if isThrowingVoidType(actual):
                resultType = try makeSimpleType(c, "error")
            else:
                resultType = try substituteType(c, actual)
            ..
        else:
            try checkType(c, value.type, scope, false)
            resultType = try substituteType(c, value.type)
            actual = try applyNumericContext(c, value.assignment, resultType, actual)
            if not (try isCompatible(c, resultType, actual)):
                c.failurePos = value.sourcePos
                c.hasFailurePos = true
                try setCallFailureContext(c, value.assignment)
                throw "initializer type is incompatible with the declared variable type"
            ..
        ..
        if isVoidType(resultType) || isThrowingType(resultType):
            throw try strgs.concat("variables cannot have void or throwing types: ", value.name)
        ..
        if value.decl != none:
            value.decl.declType = resultType
            value.decl.semanticState = 2
            kind := addrof value.decl.kind
            match kind as variable:
            case dclr.DeclKind.Variable:
                variable.type = resultType
            else:
                throw "variable expression is linked to a non-variable declaration"
            ..
            if c.checkingSpecialization && value.type == none:
                try pushLocalTypeBinding(c, value.decl, resultType)
            ..
        ..
        value.type = resultType
        ret resultType
    case nt.Expr.VarDefAssignDestructure:
        callType := try checkExpression(c, value.call, scope)
        match callType as throwing:
        case nt.Type.Throwing:
            valueType := throwing.ofType
            if isVoidType(valueType):
                throw "a throwing void call cannot be destructured"
            ..
            expectedValueType := value.type
            if expectedValueType != none:
                try checkType(c, expectedValueType, scope, false)
            ..
            if c.checkingSpecialization:
                expectedValueType = try substituteType(c, expectedValueType)
            ..
            if expectedValueType != none && not (try isCompatible(c, expectedValueType, valueType)):
                expectedShape := try typeShape(expectedValueType)
                actualShape := try typeShape(valueType)
                firstPart := try strgs.concat("destructured value type mismatch: expected ", expectedShape)
                defer firstPart.free()
                secondPart := try strgs.concat(", got ", actualShape)
                defer secondPart.free()
                throw try strgs.concat(firstPart, secondPart)
            ..
            if not c.checkingSpecialization:
                value.type = valueType
            ..
            if value.valueDecl != none && not c.checkingSpecialization:
                value.valueDecl.declType = valueType
                value.valueDecl.semanticState = 2
            ..
            if value.valueDecl != none && c.checkingSpecialization:
                try pushLocalTypeBinding(c, value.valueDecl, valueType)
            ..
            errorType := try makeSimpleType(c, "error")
            if value.errorDecl != none && not c.checkingSpecialization:
                declaredErrorType := value.errorDecl.declType
                if declaredErrorType != none:
                    try checkType(c, declaredErrorType, scope, false)
                    if not (try isCompatible(c, errorType, declaredErrorType)):
                        throw "destructured error type does not match the error type"
                    ..
                ..
                value.errorDecl.declType = errorType
                value.errorDecl.semanticState = 2
            ..
            if value.errorDecl != none && c.checkingSpecialization:
                value.errorDecl.declType = errorType
                try pushLocalTypeBinding(c, value.errorDecl, errorType)
            ..
            ret valueType
        else:
            throw "destructuring requires a throwing call"
        ..
    case nt.Expr.Sizeof:
        try checkType(c, value.operand, scope, false)
        if isVoidType(value.operand):
            throw "sizeof cannot be applied to void"
        ..
        value.type = try makeSimpleType(c, "u64")
        ret value.type
    case nt.Expr.Unary:
        operandType := try checkExpression(c, value.operand, scope)
        if value.op == tkt.KwType.MINUS:
            if not isNumericType(operandType):
                throw "unary minus requires a numeric operand"
            ..
            value.type = operandType
        elif value.op == tkt.KwType.NOT:
            if not isBoolType(operandType):
                throw "logical not requires a bool operand"
            ..
            value.type = try makeSimpleType(c, "bool")
        elif value.op == tkt.KwType.TILDE:
            if not isIntegerType(operandType):
                throw "bitwise not requires an integer operand"
            ..
            value.type = operandType
        elif value.op == tkt.KwType.ASTERIX:
            match operandType as pointer:
            case nt.Type.Pointer:
                value.type = pointer.toType
            case nt.Type.Owned:
                match pointer.ofType as ownedPointer:
                case nt.Type.Pointer:
                    value.type = ownedPointer.toType
                else:
                    throw "dereference requires a pointer"
                ..
            else:
                throw "dereference requires a pointer"
            ..
            value.category = nt.ValueCategory.Place
        elif value.op == tkt.KwType.AMPERSAND || value.op == tkt.KwType.ADDROF:
            value.type = try makePointerType(c, operandType)
        else:
            throw "unsupported unary operator"
        ..
        if value.category == nt.ValueCategory.Unresolved:
            value.category = nt.ValueCategory.Value
        ..
        value.floatingPoint = value.op == tkt.KwType.MINUS && isFloatType(operandType)
        ret value.type
    case nt.Expr.Move:
        value.type = try checkExpression(c, value.operand, scope)
        ret value.type
    case nt.Expr.Binary:
        leftType := try checkExpression(c, value.left, scope)
        rightType := try checkExpression(c, value.right, scope)
        if value.op == tkt.KwType.PLUS || value.op == tkt.KwType.MINUS || value.op == tkt.KwType.ASTERIX || value.op == tkt.KwType.SLASH || value.op == tkt.KwType.PERCENT:
            if not isNumericType(leftType) || not isNumericType(rightType):
                throw "arithmetic operators require numeric operands"
            ..
            value.type = try numericPromotion(c, leftType, rightType)
        elif value.op == tkt.KwType.CMP_LT || value.op == tkt.KwType.CMP_GT || value.op == tkt.KwType.CMP_LTEQ || value.op == tkt.KwType.CMP_GTEQ:
            if not isNumericType(leftType) || not isNumericType(rightType):
                throw "ordering comparisons require numeric operands"
            ..
            value.type = try makeSimpleType(c, "bool")
        elif value.op == tkt.KwType.CMP_EQ || value.op == tkt.KwType.CMP_NEQ:
                if not (try isCompatible(c, leftType, rightType)) && not (try isCompatible(c, rightType, leftType)):
                throw "comparison operands have incompatible types"
            ..
            value.protoEquality = try isProtocolValueType(c, leftType)
            value.stringEquality = isStringValueType(leftType, 0)
            value.type = try makeSimpleType(c, "bool")
        elif value.op == tkt.KwType.ANDAND || value.op == tkt.KwType.OROR:
            if not isBoolType(leftType) || not isBoolType(rightType):
                throw "logical operators require bool operands"
            ..
            value.type = try makeSimpleType(c, "bool")
        elif value.op == tkt.KwType.SHIFT_L || value.op == tkt.KwType.SHIFT_R:
            if not isIntegerType(leftType) || not isIntegerType(rightType):
                throw "shift operators require integer operands"
            ..
            value.type = try numericPromotion(c, leftType, rightType)
        elif value.op == tkt.KwType.AMPERSAND || value.op == tkt.KwType.CARET || value.op == tkt.KwType.PIPE:
            if isBoolType(leftType) && isBoolType(rightType):
                value.type = try makeSimpleType(c, "bool")
            elif isIntegerType(leftType) && isIntegerType(rightType):
                value.type = try numericPromotion(c, leftType, rightType)
            else:
                throw "bitwise operators require matching bool or integer operands"
            ..
        else:
            throw "unsupported binary operator"
        ..
        comparison := value.op == tkt.KwType.CMP_EQ || value.op == tkt.KwType.CMP_NEQ || value.op == tkt.KwType.CMP_LT || value.op == tkt.KwType.CMP_LTEQ || value.op == tkt.KwType.CMP_GT || value.op == tkt.KwType.CMP_GTEQ
        operationType := value.type
        if comparison:
            operationType = leftType
        ..
        value.floatingPoint = isFloatType(operationType)
        value.unsignedOperation = isUnsignedType(operationType)
        ret value.type
    case nt.Expr.DirectCall:
        if value.decl == none:
            throw "direct call has no linked declaration"
        ..
        match value.decl.kind as directKind:
        case dclr.DeclKind.Function:
            priorDiagnostic := saveCallDiagnostic(c)
            c.callDiagnosticPos = value.sourcePos
            c.callSignaturePos = value.decl.sourcePos
            c.hasCallDiagnostic = true
            if directKind.typeParams.count() != 0:
                value.type = try instantiateGenericCall(c, value.decl, value.args, nt.emptyTypeArray(), scope, addrof value.typeArgs)
            else:
                value.type = try checkCallDecl(c, value.decl, value.args, scope)
            ..
            restoreCallDiagnostic(c, priorDiagnostic)
        case dclr.DeclKind.Struct:
            if directKind.typeParams.count() != 0:
                value.type = try instantiateGenericCall(c, value.decl, value.args, nt.emptyTypeArray(), scope, addrof value.typeArgs)
            else:
                value.type = try checkCallDecl(c, value.decl, value.args, scope)
            ..
        else:
            callableType := try typeOfDecl(c, value.decl, scope)
            value.type = try checkCallableValue(c, callableType, value.args, scope)
        ..
        value.callKind = checkedDeclarationCallKind(value.decl)
        ret value.type
    case nt.Expr.TemplatedDirectCall:
        if value.decl == none:
            throw "generic call has no linked declaration"
        ..
        priorDiagnostic := saveCallDiagnostic(c)
        c.callDiagnosticPos = value.sourcePos
        c.callSignaturePos = value.decl.sourcePos
        c.hasCallDiagnostic = true
        value.type = try instantiateGenericCall(c, value.decl, value.args, value.typeArgs, scope, addrof value.typeArgs)
        value.callKind = checkedDeclarationCallKind(value.decl)
        restoreCallDiagnostic(c, priorDiagnostic)
        ret value.type
    case nt.Expr.IndirectCall:
        priorDiagnostic := saveCallDiagnostic(c)
        c.callDiagnosticPos = value.sourcePos
        c.callSignaturePos = org.FilePos(line=0, column=0)
        c.callSignatureFile = none
        match value.owner as callOwner:
        case nt.Expr.Named:
            if callOwner.decl != none:
                c.callSignaturePos = callOwner.decl.sourcePos
            ..
        case nt.Expr.MemberAccess:
            match callOwner.member as named:
            case nt.Expr.Named:
                if named.decl != none:
                    c.callSignaturePos = named.decl.sourcePos
                ..
            else:
                c.callSignaturePos = c.callSignaturePos
            ..
        else:
            c.callSignaturePos = c.callSignaturePos
        ..
        c.hasCallDiagnostic = true
        value.type = try checkIndirectCall(c, value.owner, value.args, scope, addrof value.typeArgs)
        resolution := try resolveCall(c, value.owner)
        value.callKind = resolution.kind
        value.target = resolution.target
        restoreCallDiagnostic(c, priorDiagnostic)
        ret value.type
    case nt.Expr.TemplatedIndirectCall:
        priorDiagnostic := saveCallDiagnostic(c)
        c.callDiagnosticPos = value.sourcePos
        c.callSignaturePos = org.FilePos(line=0, column=0)
        c.callSignatureFile = none
        c.hasCallDiagnostic = true
        if protoImplOperation(value.owner) != "":
            value.type = try checkProtoImplCall(c, value.owner, value.args, value.typeArgs, scope)
            resolution := try resolveCall(c, value.owner)
            value.callKind = resolution.kind
            value.target = resolution.target
            restoreCallDiagnostic(c, priorDiagnostic)
            ret value.type
        ..
        if protoViewOperation(value.owner) != "":
            value.type = try checkProtoViewCall(c, value.owner, value.args, value.typeArgs, scope)
            resolution := try resolveCall(c, value.owner)
            value.callKind = resolution.kind
            value.target = resolution.target
            restoreCallDiagnostic(c, priorDiagnostic)
            ret value.type
        ..
        _ := try checkExpression(c, value.owner, scope)
        declaration := callableDeclaration(value.owner)
        if declaration == none:
            throw "generic call target must name a generic function or type"
        ..
        value.type = try instantiateGenericCall(c, declaration, value.args, value.typeArgs, scope, addrof value.typeArgs)
        resolution := try resolveCall(c, value.owner)
        value.callKind = resolution.kind
        value.target = resolution.target
        restoreCallDiagnostic(c, priorDiagnostic)
        ret value.type
    case nt.Expr.GenericApply:
        _ := try checkExpression(c, value.owner, scope)
        declaration := callableDeclaration(value.owner)
        if declaration == none:
            throw "generic application target must name a generic declaration"
        ..
        value.type = try instantiateGenericReference(c, declaration, value.typeArgs, scope, addrof value.typeArgs)
        ret value.type
    case nt.Expr.Try:
        if c.deferDepth != 0:
            throw "try cannot be used in a deferred statement or expression"
        ..
        if c.returnType == none || not isThrowingType(c.returnType):
            throw "try requires a throwing function"
        ..
        priorTryDepth := c.tryDepth
        c.tryDepth = priorTryDepth + 1
        defer c.tryDepth = priorTryDepth
        callType := try checkExpression(c, value.call, scope)
        match callType as throwing:
        case nt.Type.Throwing:
            value.type = throwing.ofType
        else:
            throw "try requires a throwing call"
        ..
        ret value.type
    case nt.Expr.Assign:
        previousFailurePos := c.failurePos
        previousHasFailurePos := c.hasFailurePos
        c.failurePos = value.sourcePos
        c.hasFailurePos = true
        targetType := try checkExpression(c, value.assignee, scope)
        if not (try isAssignableExpr(value.assignee)):
            throw "expression is not assignable"
        ..
        try checkAssignmentTarget(c, value.assignee, scope)
        actualType := try checkExpression(c, value.expr, scope)
        actualType = try applyNumericContext(c, value.expr, targetType, actualType)
        if not (try isCompatible(c, targetType, actualType)):
            try setCallFailureContext(c, value.expr)
            if c.hasCallDiagnostic:
                c.failurePos = c.callDiagnosticPos
            ..
            throw "assignment has an incompatible value type"
        ..
        c.failurePos = previousFailurePos
        c.hasFailurePos = previousHasFailurePos
        value.type = targetType
        ret value.type
    case nt.Expr.Return:
        if c.deferDepth != 0:
            throw "ret cannot be used in a deferred statement or expression"
        ..
        if c.returnType == none:
            throw "return is not valid outside a function"
        ..
        if value.expr == none:
            if not isVoidType(c.returnType) && not isThrowingVoidType(c.returnType):
                throw "non-void function must return a value"
            ..
        else:
            expectedType := c.returnType
            if isThrowingType(expectedType):
                match expectedType as throwing:
                case nt.Type.Throwing:
                    expectedType = throwing.ofType
                else:
                    expectedType = c.returnType
                ..
            ..
            expectedType = stripOwnedType(expectedType)
            actualType nt.Type*
            match value.expr as returned:
            case nt.Expr.IndirectCall:
                if protoViewOperation(returned.owner) != "" && returned.args.count() == 0:
                    inferredProto := nt.emptyTypeArray()
                    try inferredProto.pushRight(ctx.alloc, expectedType)
                    actualType = try checkProtoViewCall(c, returned.owner, returned.args, inferredProto, scope)
                    returned.type = actualType
                    resolution := try resolveCall(c, returned.owner)
                    returned.callKind = resolution.kind
                    returned.target = resolution.target
                else:
                    actualType = try checkExpression(c, value.expr, scope)
                ..
            else:
                actualType = try checkExpression(c, value.expr, scope)
            ..
            actualType = try applyNumericContext(c, value.expr, expectedType, actualType)
            if not (try isCompatible(c, expectedType, actualType)):
                throw "return value has an incompatible type"
            ..
        ..
        ret c.returnType
    case nt.Expr.Throw:
        if c.returnType == none || not isThrowingType(c.returnType):
            throw "throw is only valid in a throwing function"
        ..
        thrownType := try checkExpression(c, value.expr, scope)
        thrownTypeName := canonicalTypeName(stripOwnedType(thrownType), 0)
        if thrownTypeName != "error" && thrownTypeName != "str":
            throw try strgs.concat("throw requires an error or string value, got ", try typeShape(thrownType))
        ..
        ret c.returnType
    ..
    throw "unsupported expression"
..

checkInlineLLVMOperation(operation str, count u64) !void:
    expected u64
    if operation == "offset": expected = 2
    elif operation == "ptrtoint" || operation == "inttoptr" || operation == "sext" || operation == "zext" || operation == "trunc" || operation == "bitcast" || operation == "sitofp" || operation == "uitofp" || operation == "fptosi" || operation == "fptoui" || operation == "reinterpret": expected = 1
    elif operation == "load_volatile": expected = 2
    elif operation == "store_volatile": expected = 3
    elif operation == "atomic_load": expected = 3
    elif operation == "atomic_store": expected = 4
    elif operation == "atomic_rmw": expected = 5
    elif operation == "cmpxchg_old": expected = 6
    elif operation == "asm_sideeffect": expected = 1
    elif operation == "sideeffect" || operation == "trap": expected = 0
    elif operation == "expect": expected = 2
    elif operation == "fence" || operation == "assume": expected = 1
    elif operation == "bswap" || operation == "bitreverse" || operation == "ctpop" || operation == "ctlz" || operation == "cttz": expected = 1
    else:
        throw "unknown inline LLVM operation"
    ..
    if count != expected:
        throw "inline LLVM operation has an invalid operand count"
    ..
..

isProtocolValueType(c Checker*, type nt.Type*) !bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.Pointer:
        ret try isProtocolValueType(c, value.toType)
    case nt.Type.Owned:
        ret try isProtocolValueType(c, value.ofType)
    case nt.Type.Named:
        if value.decl == none:
            ret false
        ..
        match value.decl.kind as declaration:
        case dclr.DeclKind.Proto:
            ret true
        case dclr.DeclKind.Alias:
            ret try isProtocolValueType(c, declaration.target)
        else:
            ret false
        ..
    else:
        ret false
    ..
..

isThrowingType(type nt.Type*) bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.Throwing:
        ret true
    else:
        ret false
    ..
..

isThrowingVoidType(type nt.Type*) bool:
    if type == none:
        ret false
    ..
    match type as value:
    case nt.Type.Throwing:
        ret isVoidType(value.ofType)
    else:
        ret false
    ..
..

isAssignableExpr(expression nt.Expr*) !bool:
    if expression == none:
        ret false
    ..
    match expression as value:
    case nt.Expr.Named:
        if value.category == nt.ValueCategory.Unresolved: throw "named expression has no checked value category" ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.MemberAccess:
        if value.category == nt.ValueCategory.Unresolved: throw "member access has no checked value category" ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.Subscript:
        if value.category == nt.ValueCategory.Unresolved: throw "subscript has no checked value category" ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.Unary:
        if value.category == nt.ValueCategory.Unresolved: throw "unary expression has no checked value category" ..
        ret value.category == nt.ValueCategory.Place
    else:
        ret false
    ..
..

checkAssignmentTarget(c Checker*, expression nt.Expr*, scope dclr.Scope*) !void:
    match expression as value:
    case nt.Expr.Named:
        if value.decl == none:
            value.decl = try resolveName(c, value.name, scope)
        ..
        match value.decl.kind as kind:
        case dclr.DeclKind.Variable:
            if kind.isConst:
                throw "cannot assign to a constant"
            ..
        case dclr.DeclKind.Argument:
            ret
        else:
            throw "declaration is not assignable"
        ..
    case nt.Expr.MemberAccess:
        match value.member as named:
        case nt.Expr.Named:
            if named.decl == none:
                throw "member assignment has no linked declaration"
            ..
            match named.decl.kind as kind:
            case dclr.DeclKind.Field:
                kind = kind
            case dclr.DeclKind.Variable:
                if kind.isConst:
                    throw "cannot assign to a constant"
                ..
            else:
                throw "member declaration is not assignable"
            ..
        else:
            throw "member assignment requires a named field"
        ..
        skipOwnerAssignment := false
        if expressionIsDottedName(value.owner):
            firstOwnerName := expressionFirstName(value.owner)
            if firstOwnerName != "" && (try isImportedAlias(c, firstOwnerName, scope)):
                skipOwnerAssignment = true
            ..
        ..
        if not skipOwnerAssignment:
            try checkAssignmentTarget(c, value.owner, scope)
        ..
    case nt.Expr.Subscript:
        ret
    case nt.Expr.Unary:
        if value.op == tkt.KwType.ASTERIX:
            ret
        ..
        throw "expression is not assignable"
    else:
        throw "expression is not assignable"
    ..
..

checkCallArgsWithTypes(c Checker*, expected nt.NodeArray[nt.Type*], actual nt.NodeArray[nt.Expr*], actualTypes nt.TypePointerArray, scope dclr.Scope*) !void:
    if expected.count() != actual.count() || actual.count() != actualTypes.count():
        throw "call argument count does not match the function signature"
    ..
    for i := 0 to actual.count():
        expectedType := try expected.get(i)
        try checkType(c, expectedType, scope, false)
        actualType := try actualTypes.get(i)
        if c.tryDepth != 0 && isThrowingType(actualType):
            match actualType as value:
            case nt.Type.Throwing:
                actualType = value.ofType
            else:
            ..
        ..
        actualType = try applyNumericContext(c, actual.get(i), expectedType, actualType)
        if not (try isCompatible(c, expectedType, actualType)):
            throw "call argument type is incompatible with the function signature"
        ..
    ..
..

expressionTypes(c Checker*, expressions nt.NodeArray[nt.Expr*], scope dclr.Scope*) !$nt.TypePointerArray:
    types := nt.emptyTypePointerArray()
    try types.reserve(ctx.alloc, expressions.count())
    for i := 0 to expressions.count():
        try types.pushRight(ctx.alloc, try checkExpression(c, expressions.get(i), scope))
    ..
    ret move types
..

checkCallArgs(c Checker*, expected nt.NodeArray[nt.Type*], actual nt.NodeArray[nt.Expr*], scope dclr.Scope*) !void:
    actualTypes := try expressionTypes(c, actual, scope)
    try checkCallArgsWithTypes(c, expected, actual, actualTypes, scope)
..

checkArrayConstructor(c Checker*, arrayExpression nt.Expr*, arguments nt.NodeArray[nt.Expr*], scope dclr.Scope*) !nt.Type*:
    match arrayExpression as array:
    case nt.Expr.Array:
        try checkType(c, array.type, scope, false)
        if array.length != none:
            lengthType := try checkExpression(c, array.length, scope)
            if not isIntegerType(lengthType):
                throw "array length must be an integer"
            ..
        ..
        expected := nt.emptyTypeArray()
        actualExpressions := nt.emptyExpressionArray()
        seenIndices := nt.emptyIndexArray()
        array.resolvedIndices = nt.emptyIndexArray()
        positionalIndex u64 = 0
        fixedLength u64 = 0
        hasFixedLength := false
        if array.length != none && (try constantExpression(c, array.length, 0)):
            fixedLength = try constantUnsignedInteger(c, array.length, 0)
            hasFixedLength = true
            array.resolvedLength = fixedLength
            array.hasResolvedLength = true
        ..
        for i := 0 to arguments.count():
            try expected.pushRight(ctx.alloc, array.type)
            argument := try arguments.get(i)
            index u64 = positionalIndex
            match argument as designated:
            case nt.Expr.Assign:
                indexType := try checkExpression(c, designated.assignee, scope)
                if not isIntegerType(indexType):
                    throw "array initializer index must be an integer"
                ..
                if not (try constantExpression(c, designated.assignee, 0)):
                    throw "array initializer index must be a compile-time constant"
                ..
                index = try constantUnsignedInteger(c, designated.assignee, 0)
                designated.resolvedFieldIndex = index
                try actualExpressions.pushRight(ctx.alloc, designated.expr)
            else:
                try actualExpressions.pushRight(ctx.alloc, argument)
            ..
            match argument as positional:
            case nt.Expr.Assign:
                positionalIndex = positionalIndex
            else:
                positionalIndex = positionalIndex + 1
            ..
            if hasFixedLength && index >= fixedLength:
                throw "array initializer index is outside the fixed array length"
            ..
            for priorIndex := 0 to seenIndices.count():
                prior := try seenIndices.get(priorIndex)
                if prior == index:
                    throw "array initializer index is specified more than once"
                ..
            ..
            try seenIndices.pushRight(ctx.alloc, index)
            try array.resolvedIndices.pushRight(ctx.alloc, index)
        ..
        actualTypes := try expressionTypes(c, actualExpressions, scope)
        try checkCallArgsWithTypes(c, expected, actualExpressions, actualTypes, scope)
        ret try makeSliceType(c, try substituteType(c, array.type))
    else:
        throw "array constructor requires an array type"
    ..
    throw "array constructor requires an array type"
..

checkCallableValue(c Checker*, callableType nt.Type*, arguments nt.NodeArray[nt.Expr*], scope dclr.Scope*) !nt.Type*:
    resolvedType := try canonicalType(callableType, 0)
    match resolvedType as value:
    case nt.Type.Function:
        try checkCallArgs(c, value.args, arguments, scope)
        ret value.returnType
    case nt.Type.Throwing:
        innerType := try canonicalType(value.ofType, 0)
        match innerType as function:
        case nt.Type.Function:
            try checkCallArgs(c, function.args, arguments, scope)
            ret try makeNodeType(c, nt.Type.Throwing(ofType=function.returnType))
        else:
            throw "expression is not callable"
        ..
    else:
        throw "expression is not callable"
    ..
..

structArgumentFieldIndex(structure dclr.Decl*, argument nt.Expr*, positionalIndex u64) !u64:
    match argument as value:
    case nt.Expr.Assign:
        match value.assignee as named:
        case nt.Expr.Named:
            fields := structure.kind
            match fields as structKind:
            case dclr.DeclKind.Struct:
                for i := 0 to structKind.fields.count():
                    field := try structKind.fields.get(i)
                    match field.kind as fieldKind:
                    case dclr.DeclKind.Field:
                        if fieldKind.name == named.name:
                            # Record the resolved field on the constructor
                            # designator so later stages use declaration
                            # identity instead of repeating a name lookup.
                            named.decl = field
                            named.type = fieldKind.type
                            value.resolvedFieldIndex = i
                            value.hasResolvedFieldIndex = true
                            ret i
                        ..
                    else:
                        continue
                    ..
                ..
            else:
                throw "constructor declaration is not a struct"
            ..
            throw "constructor names an unknown field"
        else:
            throw "constructor field initializer must use a field name"
        ..
    else:
        ret positionalIndex
    ..
    ret positionalIndex
..

structArgumentValue(argument nt.Expr*) !nt.Expr*:
    match argument as value:
    case nt.Expr.Assign:
        ret value.expr
    else:
        ret argument
    ..
..

unionVariantArgumentFieldIndex(variant dclr.Decl*, argument nt.Expr*, positionalIndex u64) !u64:
    match argument as value:
    case nt.Expr.Assign:
        match value.assignee as named:
        case nt.Expr.Named:
            match variant.kind as variantKind:
            case dclr.DeclKind.UnionVariant:
                for i := 0 to variantKind.fields.count():
                    field := try variantKind.fields.get(i)
                    match field.kind as fieldKind:
                    case dclr.DeclKind.Field:
                        if fieldKind.name == named.name:
                            named.decl = field
                            named.type = fieldKind.type
                            value.resolvedFieldIndex = i
                            value.hasResolvedFieldIndex = true
                            ret i
                        ..
                    else:
                        continue
                    ..
                ..
                throw "union variant constructor names an unknown field"
            else:
                throw "union constructor declaration is not a variant"
            ..
        else:
            throw "union variant field initializer must use a field name"
        ..
    else:
        ret positionalIndex
    ..
    ret positionalIndex
..

checkUnionVariantConstructorArgs(c Checker*, declaration dclr.Decl*, arguments nt.NodeArray[nt.Expr*], scope dclr.Scope*) !void:
    match declaration.kind as variant:
    case dclr.DeclKind.UnionVariant:
        if variant.fields.count() != arguments.count():
            throw "constructor argument count does not match the union variant fields"
        ..
        actualExpressions := try constructorArgumentExpressions(arguments)
        actualTypes := try expressionTypes(c, actualExpressions, scope)
        for i := 0 to arguments.count():
            argument := try arguments.get(i)
            fieldIndex := try unionVariantArgumentFieldIndex(declaration, argument, i)
            if fieldIndex >= variant.fields.count():
                throw "union variant constructor field index is out of bounds"
            ..
            for j := 0 to i:
                if try unionVariantArgumentFieldIndex(declaration, try arguments.get(j), j) == fieldIndex:
                    throw "constructor initializes a union variant field more than once"
                ..
            ..
            field := try variant.fields.get(fieldIndex)
            expected := try typeOfDecl(c, field, scope)
            actual := try actualTypes.get(i)
            actual = try applyNumericContext(c, actualExpressions.get(i), expected, actual)
            if not (try isCompatible(c, expected, actual)):
                throw "union variant constructor field has an incompatible type"
            ..
        ..
    else:
        throw "constructor declaration is not a union variant"
    ..
..

constructorArgumentExpressions(arguments nt.NodeArray[nt.Expr*]) !$nt.NodeArray[nt.Expr*]:
    hasFieldAssignments := false
    for i := 0 to arguments.count():
        match try arguments.get(i) as argument:
        case nt.Expr.Assign:
            hasFieldAssignments = true
        else:
            hasFieldAssignments = hasFieldAssignments
        ..
    ..
    if hasFieldAssignments == false:
        ret arguments
    ..
    values := nt.emptyExpressionArray()
    for i := 0 to arguments.count():
        try values.pushRight(ctx.alloc, try structArgumentValue(arguments.get(i)))
    ..
    ret move values
..

checkStructConstructorArgsWithTypes(c Checker*, structure dclr.Decl*, arguments nt.NodeArray[nt.Expr*], actualTypes nt.TypePointerArray, scope dclr.Scope*) !void:
    structKind := structure.kind
    match structKind as value:
    case dclr.DeclKind.Struct:
        if value.fields.count() != arguments.count() || arguments.count() != actualTypes.count():
            throw "constructor argument count does not match the struct fields"
        ..
        for i := 0 to arguments.count():
            argument := try arguments.get(i)
            fieldIndex := try structArgumentFieldIndex(structure, argument, i)
            if fieldIndex >= value.fields.count():
                throw "constructor argument index is outside the struct fields"
            ..
            for j := 0 to i:
                previousField := try structArgumentFieldIndex(structure, try arguments.get(j), j)
                if previousField == fieldIndex:
                    throw "constructor initializes a struct field more than once"
                ..
            ..
            field := try value.fields.get(fieldIndex)
            expectedType := try substituteType(c, try typeOfDecl(c, field, scope))
            argumentValue := try structArgumentValue(argument)
            actualType := try actualTypes.get(i)
            actualType = try applyNumericContext(c, argumentValue, expectedType, actualType)
            if not (try isCompatible(c, expectedType, actualType)):
                throw "constructor field initializer has an incompatible type"
            ..
        ..
    else:
        throw "constructor declaration is not a struct"
    ..
..

checkStructConstructorArgs(c Checker*, structure dclr.Decl*, arguments nt.NodeArray[nt.Expr*], scope dclr.Scope*) !void:
    actualExpressions := try constructorArgumentExpressions(arguments)
    actualTypes := try expressionTypes(c, actualExpressions, scope)
    try checkStructConstructorArgsWithTypes(c, structure, arguments, actualTypes, scope)
..

declArgTypes(c Checker*, arguments dclr.DeclArray, scope dclr.Scope*) !$nt.NodeArray[nt.Type*]:
    types := nt.emptyTypeArray()
    for i := 0 to arguments.count():
        argument := try arguments.get(i)
        try types.pushRight(ctx.alloc, try typeOfDecl(c, argument, scope))
    ..
    ret move types
..

checkCallDecl(c Checker*, declaration dclr.Decl*, arguments nt.NodeArray[nt.Expr*], scope dclr.Scope*) !nt.Type*:
    c.callSignaturePos = declaration.sourcePos
    c.callSignatureFile = try gl.files.get(declaration.module.path)
    kind := addrof declaration.kind
    match kind as value:
    case dclr.DeclKind.Function:
        expected := try declArgTypes(c, value.args, scope)
        try checkCallArgs(c, expected, arguments, scope)
        try checkType(c, value.returnType, scope, true)
        ret value.returnType
    case dclr.DeclKind.Struct:
        try checkStructConstructorArgs(c, declaration, arguments, scope)
        ret declaration.declType
    case dclr.DeclKind.UnionVariant:
        try checkUnionVariantConstructorArgs(c, declaration, arguments, scope)
        ret value.unionType
    else:
        throw "declaration is not callable"
    ..
    throw "declaration is not callable"
..

restoreBindingCount(c Checker*, count u64) void:
    c.bindingParams.length = count
    c.bindingTypes.length = count
..

methodOwnerType(declaration dclr.Decl*) !nt.Type*:
    if declaration == none || declaration.module == none:
        ret none
    ..
    file := try gl.files.get(declaration.module.path)
    for i := 0 to file.astRoot.statements.count():
        statement := nt.loadGlobalStatementNode(try file.astRoot.statements.get(i))
        match addrof statement as method:
        case nt.GlobalStmt.Method:
            body := nt.loadGlobalStatementNode(method.methodBody)
            match addrof body as function:
            case nt.GlobalStmt.Function:
                if function.header.decl == declaration:
                    ret method.ownerType
                ..
            else:
                continue
            ..
        else:
            continue
        ..
    ..
    ret none
..

genericParams(declaration dclr.Decl*) !dclr.DeclArray:
    match declaration.kind as kind:
    case dclr.DeclKind.Function:
        ownerType := try methodOwnerType(declaration)
        ownerParameters := dclr.emptyDeclArray()
        if ownerType != none:
            match ownerType as owner:
            case nt.Type.Templated:
                match owner.owner as namedOwner:
                case nt.Type.Named:
                    if namedOwner.decl != none:
                        match namedOwner.decl.kind as ownerKind:
                        case dclr.DeclKind.Struct:
                            ownerParameters = ownerKind.typeParams
                        else:
                            ownerParameters = ownerParameters
                        ..
                    ..
                else:
                    ownerParameters = ownerParameters
                ..
            else:
                ownerParameters = ownerParameters
            ..
        ..
        if ownerParameters.count() == 0:
            ret kind.typeParams
        ..
        parameters := dclr.emptyDeclArray()
        for i := 0 to ownerParameters.count():
            try parameters.pushRight(ctx.alloc, try ownerParameters.get(i))
        ..
        for i := 0 to kind.typeParams.count():
            try parameters.pushRight(ctx.alloc, try kind.typeParams.get(i))
        ..
        ret parameters
    case dclr.DeclKind.Struct:
        ret kind.typeParams
    else:
        throw "declaration does not accept generic type arguments"
    ..
..

concreteTypeArgs(c Checker*, parameters dclr.DeclArray) !$nt.NodeArray[nt.Type*]:
    args := nt.emptyTypeArray()
    for i := 0 to parameters.count():
        parameter := try parameters.get(i)
        actual := try substituteType(c, try boundType(c, parameter))
        if actual == none:
            throw "could not infer every generic type argument"
        ..
        try args.pushRight(ctx.alloc, actual)
    ..
    ret move args
..

bindExplicitTypeArgs(c Checker*, parameters dclr.DeclArray, typeArgs nt.NodeArray[nt.Type*], scope dclr.Scope*) !void:
    if parameters.count() != typeArgs.count():
        throw "generic type argument count does not match the declaration"
    ..
    for i := 0 to parameters.count():
        parameter := try parameters.get(i)
        parsedActual := try typeArgs.get(i)
        try checkType(c, parsedActual, scope, false)
        actual := try substituteType(c, parsedActual)
        try pushTypeBinding(c, parameter, actual)
    ..
..

functionInstanceType(c Checker*, declaration dclr.Decl*, args dclr.DeclArray) !$nt.Type*:
    values := nt.emptyTypeArray()
    for i := 0 to args.count():
        argument := try args.get(i)
        argumentType := try typeOfDecl(c, argument, none)
        try values.pushRight(ctx.alloc, try substituteType(c, argumentType))
    ..
    kind := declaration.kind
    match kind as function:
    case dclr.DeclKind.Function:
        result := try substituteType(c, function.returnType)
        noContext := false
        if declaration.declType != none:
            match declaration.declType as signature:
            case nt.Type.Function:
                noContext = signature.noContext
            else:
                throw "function declaration has a non-function canonical type"
            ..
        ..
        ret try makeNodeType(c, nt.Type.Function(args=move values, returnType=result, noContext=noContext))
    else:
        throw "declaration is not a function"
    ..
..

instantiateGenericCall(c Checker*, declaration dclr.Decl*, arguments nt.NodeArray[nt.Expr*], explicitTypes nt.NodeArray[nt.Type*], scope dclr.Scope*, typeArgsOut nt.NodeArray[nt.Type*]*) !nt.Type*:
    c.callSignaturePos = declaration.sourcePos
    c.callSignatureFile = try gl.files.get(declaration.module.path)
    parameters := try genericParams(declaration)
    if parameters.count() == 0:
        throw "generic arguments were provided for a non-generic declaration"
    ..
    baseCount := c.bindingParams.count()
    defer restoreBindingCount(c, baseCount)

    actualExpressions := arguments
    match declaration.kind as callable:
    case dclr.DeclKind.Function:
        if callable.args.count() != arguments.count():
            throw "call argument count does not match the function signature"
        ..
    case dclr.DeclKind.Struct:
        if callable.fields.count() != arguments.count():
            throw "constructor argument count does not match the struct fields"
        ..
        actualExpressions = try constructorArgumentExpressions(arguments)
    else:
        throw "declaration is not a generic function or struct"
    ..
    actualTypes := try expressionTypes(c, actualExpressions, scope)

    if explicitTypes.count() != 0:
        try bindExplicitTypeArgs(c, parameters, explicitTypes, scope)
    else:
        match declaration.kind as callable:
        case dclr.DeclKind.Function:
            for i := 0 to arguments.count():
                formal := try callable.args.get(i)
                formalType := try typeOfDecl(c, formal, scope)
                actualType := try actualTypes.get(i)
                try bindTypePattern(c, formalType, actualType, 0)
            ..
        case dclr.DeclKind.Struct:
            for i := 0 to arguments.count():
                fieldIndex := try structArgumentFieldIndex(declaration, try arguments.get(i), i)
                formal := try callable.fields.get(fieldIndex)
                formalType := try typeOfDecl(c, formal, scope)
                actualType := try actualTypes.get(i)
                try bindTypePattern(c, formalType, actualType, 0)
            ..
        else:
            throw "declaration is not a generic function or struct"
        ..
    ..

    instanceArgs := try concreteTypeArgs(c, parameters)
    if typeArgsOut != none:
        typeArgsOut.data = instanceArgs.data
        typeArgsOut.length = instanceArgs.length
        typeArgsOut.capacity = instanceArgs.capacity
    ..
    match declaration.kind as kind:
    case dclr.DeclKind.Function:
        formalTypes := nt.emptyTypeArray()
        for i := 0 to kind.args.count():
            formal := try kind.args.get(i)
            formalType := try substituteType(c, try typeOfDecl(c, formal, scope))
            try formalTypes.pushRight(ctx.alloc, formalType)
        ..
        try checkCallArgsWithTypes(c, formalTypes, arguments, actualTypes, scope)
        concreteType := try functionInstanceType(c, declaration, kind.args)
        allConcrete := true
        for i := 0 to instanceArgs.count():
            allConcrete = allConcrete && not (try containsUnboundTypeParameter(c, instanceArgs.get(i), 0))
        ..
        if allConcrete:
            try enqueueSpecialization(c, declaration, instanceArgs, concreteType, true)
        ..
        result := try substituteType(c, kind.returnType)
        ret result
    case dclr.DeclKind.Struct:
        try checkStructConstructorArgsWithTypes(c, declaration, arguments, actualTypes, scope)
        concreteType := try makeNodeType(c, nt.Type.Templated(owner=declaration.declType, args=instanceArgs))
        allConcrete := true
        for i := 0 to instanceArgs.count():
            allConcrete = allConcrete && not (try containsUnboundTypeParameter(c, instanceArgs.get(i), 0))
        ..
        if allConcrete:
            try enqueueSpecialization(c, declaration, instanceArgs, concreteType, false)
        ..
        ret concreteType
    else:
        throw "declaration is not a generic function or struct"
    ..
..

instantiateGenericReference(c Checker*, declaration dclr.Decl*, explicitTypes nt.NodeArray[nt.Type*], scope dclr.Scope*, typeArgsOut nt.NodeArray[nt.Type*]*) !nt.Type*:
    parameters := try genericParams(declaration)
    if parameters.count() == 0:
        throw "generic arguments were provided for a non-generic declaration"
    ..
    baseCount := c.bindingParams.count()
    defer restoreBindingCount(c, baseCount)
    try bindExplicitTypeArgs(c, parameters, explicitTypes, scope)
    instanceArgs := try concreteTypeArgs(c, parameters)
    if typeArgsOut != none:
        typeArgsOut.data = instanceArgs.data
        typeArgsOut.length = instanceArgs.length
        typeArgsOut.capacity = instanceArgs.capacity
    ..
    match declaration.kind as kind:
    case dclr.DeclKind.Function:
        concreteType := try functionInstanceType(c, declaration, kind.args)
        allConcrete := true
        for i := 0 to instanceArgs.count():
            allConcrete = allConcrete && not (try containsUnboundTypeParameter(c, instanceArgs.get(i), 0))
        ..
        if allConcrete:
            try enqueueSpecialization(c, declaration, instanceArgs, concreteType, true)
        ..
        ret concreteType
    case dclr.DeclKind.Struct:
        concreteType := try makeNodeType(c, nt.Type.Templated(owner=declaration.declType, args=instanceArgs))
        allConcrete := true
        for i := 0 to instanceArgs.count():
            allConcrete = allConcrete && not (try containsUnboundTypeParameter(c, instanceArgs.get(i), 0))
        ..
        if allConcrete:
            try enqueueSpecialization(c, declaration, instanceArgs, concreteType, false)
        ..
        ret concreteType
    else:
        throw "declaration does not support generic application"
    ..
..

callableDeclaration(expression nt.Expr*) dclr.Decl*:
    if expression == none:
        ret none
    ..
    match expression as value:
    case nt.Expr.Named:
        ret value.decl
    case nt.Expr.MemberAccess:
        match value.member as named:
        case nt.Expr.Named:
            ret named.decl
        else:
            ret none
        ..
    else:
        ret none
    ..
..

resolveCall(c Checker*, owner nt.Expr*) !CallResolution:
    viewOperation := protoViewOperation(owner)
    if viewOperation == "proto": ret CallResolution(kind=nt.CallKind.ProtoView, target=none) ..
    if viewOperation == "protoBorrow": ret CallResolution(kind=nt.CallKind.ProtoViewBorrow, target=none) ..
    implementationOperation := protoImplOperation(owner)
    if implementationOperation == "impl": ret CallResolution(kind=nt.CallKind.ProtoImpl, target=none) ..
    if implementationOperation == "implBorrow": ret CallResolution(kind=nt.CallKind.ProtoImplBorrow, target=none) ..
    match owner as ownerValue:
    case nt.Expr.Array:
        ret CallResolution(kind=nt.CallKind.ArrayConstructor, target=none)
    case nt.Expr.MemberAccess:
        if ownerValue.isProtoMethod:
            ret CallResolution(kind=nt.CallKind.ProtoMethod, target=callableDeclaration(owner))
        ..
    else:
        owner = owner
    ..
    target := callableDeclaration(owner)
    if target == none:
        ret CallResolution(kind=nt.CallKind.Indirect, target=none)
    ..
    match target.kind as targetKind:
    case dclr.DeclKind.Function:
        if target.receiverDecl != none:
            ret CallResolution(kind=nt.CallKind.StaticMethod, target=target)
        ..
        ret CallResolution(kind=nt.CallKind.FunctionCall, target=target)
    case dclr.DeclKind.Struct:
        ret CallResolution(kind=nt.CallKind.StructConstructor, target=target)
    case dclr.DeclKind.UnionVariant:
        ret CallResolution(kind=nt.CallKind.UnionConstructor, target=target)
    else:
        ret CallResolution(kind=nt.CallKind.Indirect, target=none)
    ..
..

checkedDeclarationCallKind(target dclr.Decl*) nt.CallKind:
    if target == none:
        ret nt.CallKind.Unresolved
    ..
    match target.kind as kind:
    case dclr.DeclKind.Function:
        ret nt.CallKind.FunctionCall
    case dclr.DeclKind.Struct:
        ret nt.CallKind.StructConstructor
    case dclr.DeclKind.UnionVariant:
        ret nt.CallKind.UnionConstructor
    else:
        ret nt.CallKind.Unresolved
    ..
..

protoViewOperation(expression nt.Expr*) str:
    if expression == none:
        ret ""
    ..
    match expression as value:
    case nt.Expr.MemberAccess:
        match value.member as name:
        case nt.Expr.Named:
            if name.name == "proto" || name.name == "protoBorrow":
                ret name.name
            ..
        else:
            ret ""
        ..
    else:
        ret ""
    ..
    ret ""
..

protoImplOperation(expression nt.Expr*) str:
    if expression == none:
        ret ""
    ..
    match expression as value:
    case nt.Expr.MemberAccess:
        match value.member as name:
        case nt.Expr.Named:
            if name.name == "impl" || name.name == "implBorrow":
                ret name.name
            ..
        else:
            ret ""
        ..
    else:
        ret ""
    ..
    ret ""
..

checkProtoImplCall(c Checker*, owner nt.Expr*, arguments nt.NodeArray[nt.Expr*], typeArgs nt.NodeArray[nt.Type*], scope dclr.Scope*) !nt.Type*:
    if arguments.count() != 0 || typeArgs.count() != 1:
        throw "implementation conversion requires one type argument and no value arguments"
    ..
    implementationExpr nt.Expr* = none
    match owner as member:
    case nt.Expr.MemberAccess:
        implementationExpr = member.owner
    else:
        throw "implementation conversion requires a prototype receiver"
    ..
    prototypeType := stripOwnedType(try checkExpression(c, implementationExpr, scope))
    match prototypeType as pointerPrototype:
    case nt.Type.Pointer:
        prototypeType = pointerPrototype.toType
    else:
    ..
    prototypeDecl := try typeDeclaration(c, prototypeType)
    match prototypeDecl.kind as prototypeKind:
    case dclr.DeclKind.Proto:
        prototypeKind = prototypeKind
    else:
        throw "implementation conversion requires a prototype value"
    ..
    implementationType := try typeArgs.get(0)
    try checkType(c, implementationType, scope, false)
    implementationDecl := try typeDeclaration(c, implementationType)
    implementationKind := implementationDecl.kind
    implementationTypes := nt.emptyTypeArray()
    match implementationKind as concrete:
    case dclr.DeclKind.Struct:
        implementationTypes = concrete.implements
    case dclr.DeclKind.Union:
        implementationTypes = concrete.implements
    else:
        throw "implementation conversion target must be a struct or union"
    ..
    implements := false
    for i := 0 to implementationTypes.count():
        candidate := try implementationTypes.get(i)
        try checkType(c, candidate, scope, false)
        if try sameType(candidate, prototypeType, 0):
            implements = true
            break
        ..
    ..
    if not implements:
        throw "implementation type does not implement the prototype"
    ..
    resultType := implementationType
    if protoImplOperation(owner) == "implBorrow":
        resultType = try makePointerType(c, implementationType)
    ..
    ret try makeNodeType(c, nt.Type.Throwing(ofType=resultType))
..

checkProtoViewCall(c Checker*, owner nt.Expr*, arguments nt.NodeArray[nt.Expr*], typeArgs nt.NodeArray[nt.Type*], scope dclr.Scope*) !nt.Type*:
    if arguments.count() != 0:
        throw "proto view operations do not accept value arguments"
    ..
    if typeArgs.count() > 1:
        throw "proto view operation accepts at most one prototype type argument"
    ..

    implementationExpr nt.Expr* = none
    match owner as member:
    case nt.Expr.MemberAccess:
        implementationExpr = member.owner
    else:
        throw "proto view operation requires an implementation receiver"
    ..

    implementationType := try checkExpression(c, implementationExpr, scope)
    implementationDecl := try typeDeclaration(c, implementationType)
    implementationTypes := nt.emptyTypeArray()
    implementationKind := implementationDecl.kind
    match implementationKind as value:
    case dclr.DeclKind.Struct:
        implementationTypes = value.implements
    case dclr.DeclKind.Union:
        implementationTypes = value.implements
    else:
        throw "proto view receiver must be a struct or union implementation"
    ..

    targetType nt.Type* = none
    if typeArgs.count() == 1:
        targetType = try typeArgs.get(0)
        try checkType(c, targetType, scope, false)
    else:
        if implementationTypes.count() != 1:
            throw "prototype type must be explicit when the implementation has zero or multiple prototypes"
        ..
        targetType = try implementationTypes.get(0)
    ..

    targetDecl := try typeDeclaration(c, targetType)
    match targetDecl.kind as targetKind:
    case dclr.DeclKind.Proto:
        targetKind = targetKind
    else:
        throw "proto view target must be a prototype"
    ..

    implementsTarget := false
    for i := 0 to implementationTypes.count():
        implementedType := try implementationTypes.get(i)
        try checkType(c, implementedType, scope, false)
        if try sameType(targetType, implementedType, 0):
            implementsTarget = true
            break
        ..
    ..
    if not implementsTarget:
        throw "implementation does not implement the requested prototype"
    ..
    ret targetType
..

checkIndirectCall(c Checker*, owner nt.Expr*, arguments nt.NodeArray[nt.Expr*], scope dclr.Scope*, typeArgsOut nt.NodeArray[nt.Type*]*) !nt.Type*:
    if protoViewOperation(owner) != "":
        ret try checkProtoViewCall(c, owner, arguments, nt.emptyTypeArray(), scope)
    ..
    match owner as array:
    case nt.Expr.Array:
        ret try checkArrayConstructor(c, owner, arguments, scope)
    else:
    ..
    ownerType := try checkExpression(c, owner, scope)
    match owner as directOwner:
    case nt.Expr.Named:
        if directOwner.decl != none:
            match directOwner.decl.kind as directKind:
            case dclr.DeclKind.Function:
                if directKind.typeParams.count() != 0:
                    ret try instantiateGenericCall(c, directOwner.decl, arguments, nt.emptyTypeArray(), scope, typeArgsOut)
                ..
                ret try checkCallDecl(c, directOwner.decl, arguments, scope)
            case dclr.DeclKind.Struct:
                if directKind.typeParams.count() != 0:
                    ret try instantiateGenericCall(c, directOwner.decl, arguments, nt.emptyTypeArray(), scope, typeArgsOut)
                ..
                ret try checkCallDecl(c, directOwner.decl, arguments, scope)
            else:
                ownerType = ownerType
            ..
        ..
    case nt.Expr.MemberAccess:
        match directOwner.member as directMember:
        case nt.Expr.Named:
            if directMember.decl != none:
                c.callSignaturePos = directMember.decl.sourcePos
                c.callSignatureFile = try gl.files.get(directMember.decl.module.path)
                match directMember.decl.kind as memberKind:
                case dclr.DeclKind.Function:
                    parameters := try genericParams(directMember.decl)
                    if parameters.count() != 0:
                        baseCount := c.bindingParams.count()
                        ownerParameterCount := parameters.count() - memberKind.typeParams.count()
                        if ownerParameterCount != 0:
                            receiverType := try checkExpression(c, directOwner.owner, scope)
                            try bindMemberOwnerType(c, receiverType)
                        ..
                        result := try instantiateGenericCall(c, directMember.decl, arguments, nt.emptyTypeArray(), scope, typeArgsOut)
                        restoreBindingCount(c, baseCount)
                        ret result
                    ..
                    ownerType = ownerType
                case dclr.DeclKind.Struct:
                    if memberKind.typeParams.count() != 0:
                        ret try instantiateGenericCall(c, directMember.decl, arguments, nt.emptyTypeArray(), scope, typeArgsOut)
                    ..
                    ret try checkCallDecl(c, directMember.decl, arguments, scope)
                case dclr.DeclKind.UnionVariant:
                    ret try checkCallDecl(c, directMember.decl, arguments, scope)
                else:
                ..
                ownerType = ownerType
            ..
        else:
            ownerType = ownerType
        ..
    else:
        ownerType = ownerType
    ..
    canonicalOwnerType := try canonicalType(ownerType, 0)
    match canonicalOwnerType as namedOwner:
    case nt.Type.Named:
        if namedOwner.decl != none:
            match namedOwner.decl.kind as declarationKind:
            case dclr.DeclKind.Struct:
                ret try checkCallDecl(c, namedOwner.decl, arguments, scope)
            case dclr.DeclKind.UnionVariant:
                ret try checkCallDecl(c, namedOwner.decl, arguments, scope)
            case dclr.DeclKind.Function:
                ret try checkCallDecl(c, namedOwner.decl, arguments, scope)
            else:
                namedOwner = namedOwner
            ..
        ..
    else:
        
    ..
    ret try checkCallableValue(c, ownerType, arguments, scope)
..

constantExpression(c Checker*, expression nt.Expr*, depth u64) !bool:
    if expression == none || depth > 64:
        ret false
    ..
    match expression as value:
    case nt.Expr.Literal:
        ret true
    case nt.Expr.CompilerKnown:
        ret true
    case nt.Expr.Named:
        if value.decl == none:
            ret false
        ..
        match value.decl.kind as declaration:
        case dclr.DeclKind.Function:
            ret true
        case dclr.DeclKind.Variable:
            ret declaration.isConst && declaration.initializer != none && (try constantExpression(c, declaration.initializer, depth + 1))
        case dclr.DeclKind.EnumVariant:
            ret true
        else:
            ret false
        ..
    case nt.Expr.DirectCall:
        if value.decl == none:
            ret false
        ..
        match value.decl.kind as declaration:
        case dclr.DeclKind.Struct:
            for i := 0 to value.args.count():
                if not (try constantExpression(c, value.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret true
        else:
            ret false
        ..
    case nt.Expr.TemplatedDirectCall:
        if value.decl == none:
            ret false
        ..
        match value.decl.kind as declaration:
        case dclr.DeclKind.Struct:
            for i := 0 to value.args.count():
                if not (try constantExpression(c, value.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret true
        else:
            ret false
        ..
    case nt.Expr.IndirectCall:
        match value.owner as array:
        case nt.Expr.Array:
            if array.length != none && not (try constantExpression(c, array.length, depth + 1)):
                ret false
            ..
            for i := 0 to value.args.count():
                if not (try constantExpression(c, value.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret true
        else:
        ..
        declaration := callableDeclaration(value.owner)
        if declaration == none:
            ret false
        ..
        match declaration.kind as constructor:
        case dclr.DeclKind.Struct:
            for i := 0 to value.args.count():
                if not (try constantExpression(c, value.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret true
        else:
            ret false
        ..
    case nt.Expr.MemberAccess:
        match value.member as namedMember:
        case nt.Expr.Named:
            if namedMember.decl != none:
                match namedMember.decl.kind as declaration:
                case dclr.DeclKind.EnumVariant:
                    ret true
                else:
                    ret false
                ..
            ..
        else:
            ret false
        ..
        ret false
    case nt.Expr.TemplatedIndirectCall:
        declaration := callableDeclaration(value.owner)
        if declaration == none:
            match value.owner as generic:
            case nt.Expr.GenericApply:
                declaration = callableDeclaration(generic.owner)
            else:
                declaration = none
            ..
        ..
        if declaration == none:
            ret false
        ..
        match declaration.kind as constructor:
        case dclr.DeclKind.Struct:
            for i := 0 to value.args.count():
                if not (try constantExpression(c, value.args.get(i), depth + 1)):
                    ret false
                ..
            ..
            ret true
        else:
            ret false
        ..
    case nt.Expr.Assign:
        ret try constantExpression(c, value.expr, depth + 1)
    else:
        ret false
    ..
..

constantUnsignedInteger(c Checker*, expression nt.Expr*, depth u64) !u64:
    if expression == none || depth > 64:
        throw "array index is not a valid compile-time integer"
    ..
    match expression as value:
    case nt.Expr.Literal:
        match value.literal as literal:
        case nt.Literal.Number:
            ret try parseUnsignedConstant(literal.value)
        case nt.Literal.HexNumber:
            ret try parseUnsignedConstant(literal.value)
        case nt.Literal.Char8:
            if literal.value.countBytes() != 1:
                throw "array index character constant must contain one byte"
            ..
            ret cast.u8to64(strgs.byteAt(literal.value, 0))
        case nt.Literal.Char32:
            input u8[] = slices.fromPtr(strgs.toPtr(literal.value), literal.value.countBytes())
            codepoint := try utf8.decode(input)
            ret cast.u32to64(codepoint.value)
        else:
            throw "array index is not an unsigned integer constant"
        ..
    case nt.Expr.CompilerKnown:
        if value.resolvedValue == "":
            throw "compiler-known array index has no resolved value"
        ..
        ret try strconv.parseUint(value.resolvedValue)
    case nt.Expr.Named:
        if value.decl == none:
            throw "array index name is unresolved"
        ..
        match value.decl.kind as declaration:
        case dclr.DeclKind.Variable:
            if not declaration.isConst || declaration.initializer == none:
                throw "array index name is not a constant variable"
            ..
            ret try constantUnsignedInteger(c, declaration.initializer, depth + 1)
        case dclr.DeclKind.EnumVariant:
            if value.decl.enumInitializer == none:
                ret value.decl.enumIndex
            ..
            ret try constantUnsignedInteger(c, value.decl.enumInitializer, depth + 1)
        else:
            throw "array index name is not an integer constant"
        ..
    case nt.Expr.MemberAccess:
        match value.member as member:
        case nt.Expr.Named:
            if member.decl == none:
                throw "array index member is unresolved"
            ..
            match member.decl.kind as declaration:
            case dclr.DeclKind.EnumVariant:
                if member.decl.enumInitializer == none:
                    ret member.decl.enumIndex
                ..
                ret try constantUnsignedInteger(c, member.decl.enumInitializer, depth + 1)
            else:
                throw "array index member is not an integer enum value"
            ..
        else:
            throw "array index member is unresolved"
        ..
    case nt.Expr.Move:
        ret try constantUnsignedInteger(c, value.operand, depth + 1)
    case nt.Expr.Assign:
        ret try constantUnsignedInteger(c, value.expr, depth + 1)
    else:
        throw "array index is not a supported compile-time integer"
    ..
..

parseUnsignedConstant(value str) !u64:
    count := value.countBytes()
    base u64 = 10
    start u64 = 0
    if count > 2 && strgs.byteAt(value, 0) == 48 && (strgs.byteAt(value, 1) == 120 || strgs.byteAt(value, 1) == 88):
        base = 16
        start = 2
    ..
    if start == count:
        throw "empty integer constant"
    ..
    result u64 = 0
    for i := start to count:
        character := strgs.byteAt(value, i)
        digit u64
        if character >= 48 && character <= 57:
            digit = cast.u8to64(character - 48)
        elif base == 16 && character >= 65 && character <= 70:
            digit = cast.u8to64(character - 65) + 10
        elif base == 16 && character >= 97 && character <= 102:
            digit = cast.u8to64(character - 97) + 10
        else:
            throw "invalid integer constant"
        ..
        maximum u64 = 18446744073709551615
        if digit >= base || result > maximum / base || (result == maximum / base && digit > maximum % base):
            throw "integer constant overflows u64"
        ..
        result = result * base + digit
    ..
    ret result
..

checkVariableDeclaration(c Checker*, declaration dclr.Decl*, scope dclr.Scope*) !nt.Type*:
    kind := addrof declaration.kind
    match kind as value:
    case dclr.DeclKind.Variable:
        if not c.checkingSpecialization && declaration.semanticState == 1:
            throw "cyclic inferred variable type"
        ..
        if not c.checkingSpecialization && declaration.semanticState == 2 && declaration.declType != none:
            ret declaration.declType
        ..
        if not c.checkingSpecialization:
            declaration.semanticState = 1
        ..
        resolvedType := value.type
        if value.type != none:
            try checkType(c, value.type, scope, false)
        ..
        if value.initializer != none:
            initializerType := try checkExpression(c, value.initializer, scope)
            if value.isConst && not (try constantExpression(c, value.initializer, 0)):
                throw "constant initializer must be a compile-time constant"
            ..
            if resolvedType != none:
                initializerType = try applyNumericContext(c, value.initializer, resolvedType, initializerType)
            ..
            if resolvedType == none:
                resolvedType = initializerType
            elif not (try isCompatible(c, try substituteType(c, resolvedType), initializerType)):
                c.failurePos = declaration.sourcePos
                c.hasFailurePos = true
                try setCallFailureContext(c, value.initializer)
                throw "variable initializer has an incompatible type"
            ..
        ..
        if resolvedType == none:
            throw "variable type cannot be inferred without an initializer"
        ..
        resolvedType = try substituteType(c, resolvedType)
        if isVoidType(resolvedType) || isThrowingType(resolvedType):
            throw "variables cannot have void or throwing types"
        ..
        if c.checkingSpecialization:
            declaration.semanticState = 0
            ret try substituteType(c, resolvedType)
        ..
        value.type = resolvedType
        declaration.declType = resolvedType
        declaration.semanticState = 2
        ret resolvedType
    else:
        throw "declaration is not a variable"
    ..
..

typeOfDecl(c Checker*, declaration dclr.Decl*, scope dclr.Scope*) !nt.Type*:
    if c.checkingSpecialization:
        localType := try boundType(c, declaration)
        if localType != none:
            ret localType
        ..
    ..
    previousFile := c.file
    previousModule := c.module
    if declaration.module != none && c.module != declaration.module:
        c.file = try gl.files.get(declaration.module.path)
        c.module = declaration.module
    ..
    defer:
        c.file = previousFile
        c.module = previousModule
    ..
    declarationScope := scope
    if declaration.sourceHeader != none:
        declarationScope = declaration.sourceHeader.scope
    elif declaration.module != none && declaration.owner.scope != 0:
        declarationScope = try declaration.module.getScope(declaration.owner.scope)
    elif scope != none && declaration.module != none && scope.module != declaration.module:
        declarationScope = none
    ..
    if declaration.declType != none:
        try checkType(c, declaration.declType, declarationScope, true)
        ret try substituteType(c, declaration.declType)
    ..
    kind := addrof declaration.kind
    match kind as value:
    case dclr.DeclKind.Variable:
        ret try checkVariableDeclaration(c, declaration, declarationScope)
    case dclr.DeclKind.Argument:
        try checkType(c, value.type, declarationScope, false)
        if not c.checkingSpecialization:
            declaration.declType = value.type
        ..
        ret value.type
    case dclr.DeclKind.Field:
        try checkType(c, value.type, declarationScope, false)
        if not c.checkingSpecialization:
            declaration.declType = value.type
        ..
        ret value.type
    case dclr.DeclKind.EnumVariant:
        if not c.checkingSpecialization:
            declaration.declType = value.type
        ..
        ret value.type
    case dclr.DeclKind.Alias:
        try checkType(c, value.target, declarationScope, false)
        if not c.checkingSpecialization:
            declaration.declType = value.target
        ..
        ret value.target
    case dclr.DeclKind.Function:
        throw "function declaration has no parser-generated type"
    case dclr.DeclKind.Struct:
        throw "struct declaration has no parser-generated type"
    case dclr.DeclKind.Enum:
        throw "enum declaration has no parser-generated type"
    case dclr.DeclKind.Union:
        throw "union declaration has no parser-generated type"
    case dclr.DeclKind.Proto:
        throw "prototype declaration has no parser-generated type"
    case dclr.DeclKind.TypeParameter:
        ret declaration.declType
    else:
        throw "declaration cannot be used as a value"
    ..
..

checkStatement(c Checker*, statement nt.Stmt*, scope dclr.Scope*) !void:
    if statement == none:
        ret
    ..
    match statement as value:
    case nt.Stmt.Body:
        throw "body cannot appear as a standalone statement"
    case nt.Stmt.Expression:
        _ := try checkExpression(c, value.expr, scope)
    case nt.Stmt.Break:
        if c.loopDepth == 0:
            throw "break is only valid inside a loop"
        ..
    case nt.Stmt.Continue:
        if c.loopDepth == 0:
            throw "continue is only valid inside a loop"
        ..
    case nt.Stmt.Defer:
        if c.deferDepth != 0:
            throw "a defer body cannot contain another defer"
        ..
        if value.body != none:
            priorDeferDepth := c.deferDepth
            c.deferDepth = priorDeferDepth + 1
            defer c.deferDepth = priorDeferDepth
            try checkBody(c, value.body)
        else:
            priorDeferDepth := c.deferDepth
            c.deferDepth = priorDeferDepth + 1
            defer c.deferDepth = priorDeferDepth
            _ := try checkExpression(c, value.expr, scope)
        ..
    case nt.Stmt.OnError:
        if value.expr != none:
            priorDeferDepth := c.deferDepth
            c.deferDepth = priorDeferDepth + 1
            defer c.deferDepth = priorDeferDepth
            _ := try checkExpression(c, value.expr, scope)
        ..
        if value.body != none:
            priorDeferDepth := c.deferDepth
            c.deferDepth = priorDeferDepth + 1
            defer c.deferDepth = priorDeferDepth
            try checkBody(c, value.body)
        ..
    case nt.Stmt.Unsafe:
        priorUnsafeDepth := c.unsafeDepth
        c.unsafeDepth = priorUnsafeDepth + 1
        defer c.unsafeDepth = priorUnsafeDepth
        if value.body != none:
            try checkBody(c, value.body)
        elif value.expr != none:
            _ := try checkExpression(c, value.expr, scope)
        ..
    case nt.Stmt.Bounded:
        for i := 0 to value.predicates.count():
            predicateType := try checkExpression(c, value.predicates.get(i), scope)
            if not isBoolType(predicateType):
                throw "bounded predicates must have bool type"
            ..
        ..
        for i := 0 to value.pointers.count():
            pointerType := try checkExpression(c, value.pointers.get(i), scope)
            extentType := try checkExpression(c, value.extents.get(i), scope)
            if not isPointerType(pointerType) || not isIntegerType(extentType):
                throw "bounded pointer extents require a pointer and integer count"
            ..
        ..
        try checkBody(c, value.body)
    case nt.Stmt.Match:
        matchType := try checkExpression(c, value.expression, scope)
        match matchType as pointerType:
        case nt.Type.Pointer:
            value.pointerMode = true
        else:
            value.pointerMode = false
        ..
        matchBindingBase := c.bindingParams.count()
        defer restoreBindingCount(c, matchBindingBase)
        if value.bindingDecl != none:
            if c.checkingSpecialization:
                try pushLocalTypeBinding(c, value.bindingDecl, matchType)
            else:
                value.bindingDecl.declType = matchType
                value.bindingDecl.semanticState = 2
            ..
        ..
        matchDecl := try typeDeclaration(c, matchType)
        matchKind := matchDecl.kind
        matchScope dclr.Scope* = none
        match matchKind as typeKind:
        case dclr.DeclKind.Union:
            matchScope = typeKind.scope
        else:
            throw "match expression must have a union type"
        ..
        seenVariants := dclr.emptyDeclArray()
        for i := 0 to value.cases.count():
            item := try value.cases.get(i)
            caseDecl := try resolveNamedDecl(c, item.variant, scope)
            if caseDecl.module != matchDecl.module || caseDecl.owner.scope != matchScope.id:
                throw "match case is not a variant of the matched union"
            ..
            item.decl = caseDecl
            for j := 0 to seenVariants.count():
                prior := try seenVariants.get(j)
                if prior == caseDecl:
                    throw "match contains a duplicate union variant"
                ..
            ..
            try seenVariants.pushRight(ctx.alloc, caseDecl)
            caseBindingBase := c.bindingParams.count()
            if value.bindingDecl != none:
                narrowedType := caseDecl.declType
                match matchType as original:
                case nt.Type.Pointer:
                    narrowedType = try makePointerType(c, narrowedType)
                else:
                    narrowedType = narrowedType
                ..
                if c.checkingSpecialization:
                    try pushLocalTypeBinding(c, value.bindingDecl, narrowedType)
                else:
                    value.bindingDecl.declType = narrowedType
                    value.bindingDecl.semanticState = 2
                ..
            ..
            try checkBody(c, item.body)
            restoreBindingCount(c, caseBindingBase)
        ..
        if value.elseBody != none:
            if value.bindingDecl != none:
                if c.checkingSpecialization:
                    try pushLocalTypeBinding(c, value.bindingDecl, matchType)
                else:
                    value.bindingDecl.declType = matchType
                    value.bindingDecl.semanticState = 2
                ..
            ..
            try checkBody(c, value.elseBody)
            restoreBindingCount(c, matchBindingBase)
        else:
            unionKind := matchDecl.kind
            match unionKind as unionValue:
            case dclr.DeclKind.Union:
                if seenVariants.count() != unionValue.variants.count():
                    throw "non-exhaustive match requires an else arm"
                ..
            else:
                throw "match expression must have a union type"
            ..
        ..
    case nt.Stmt.LLVM:
        ret
    case nt.Stmt.If:
        conditionType := try checkExpression(c, value.condition, scope)
        if not isBoolType(conditionType):
            c.failurePos = value.sourcePos
            c.hasFailurePos = true
            throw "if condition must have bool type"
        ..
        try checkBody(c, value.body)
        try checkStatement(c, value.next, scope)
    case nt.Stmt.Elif:
        conditionType := try checkExpression(c, value.condition, scope)
        if not isBoolType(conditionType):
            c.failurePos = value.sourcePos
            c.hasFailurePos = true
            throw "elif condition must have bool type"
        ..
        try checkBody(c, value.body)
        try checkStatement(c, value.next, scope)
    case nt.Stmt.Else:
        try checkBody(c, value.body)
    case nt.Stmt.Loop:
        conditionType := try checkExpression(c, value.condition, scope)
        if not isBoolType(conditionType):
            c.failurePos = value.sourcePos
            c.hasFailurePos = true
            throw "loop condition must have bool type"
        ..
        c.loopDepth = c.loopDepth + 1
        try checkBody(c, value.body)
        c.loopDepth = c.loopDepth - 1
    case nt.Stmt.ForLoop:
        boundExpressionType := try checkExpression(c, value.bound, value.scope)
        match value.index as index:
        case nt.Expr.VarDefAssign:
            if index.type == none && isIntegerType(boundExpressionType):
                initialType := try checkExpression(c, index.assignment, value.scope)
                if isIntegerType(initialType):
                    contextualType := try applyNumericContext(c, index.assignment, boundExpressionType, initialType)
                    if try sameType(contextualType, boundExpressionType, 0):
                        index.type = boundExpressionType
                        if index.decl != none && not c.checkingSpecialization:
                            index.decl.declType = boundExpressionType
                            index.decl.kind = dclr.DeclKind.Variable(name=index.name, type=boundExpressionType, initializer=none, isGlobal=false, isConst=false)
                        ..
                    ..
                ..
            ..
        else:
        ..
        indexType := try checkExpression(c, value.index, value.scope)
        if not isIntegerType(indexType) || not isIntegerType(boundExpressionType):
            throw "for-loop index and bound must be integers"
        ..
        if not (try sameType(indexType, boundExpressionType, 0)):
            boundExpressionType = try applyNumericContext(c, value.bound, indexType, boundExpressionType)
        ..
        if not (try sameType(indexType, boundExpressionType, 0)):
            throw "for-loop index and bound must have the same type"
        ..
        c.loopDepth = c.loopDepth + 1
        try checkBody(c, value.body)
        c.loopDepth = c.loopDepth - 1
    ..
..

checkBody(c Checker*, body nt.Stmt*) !void:
    match body as value:
    case nt.Stmt.Body:
        for i := 0 to value.statements.count():
            try checkStatement(c, value.statements.get(i), value.scope)
        ..
    else:
        try checkStatement(c, body, none)
    ..
..

statementAlwaysReturns(statement nt.Stmt*) !bool:
    if statement == none:
        ret false
    ..
    match statement as value:
    case nt.Stmt.Expression:
        if value.expr == none:
            ret false
        ..
        match value.expr as result:
        case nt.Expr.Return:
            ret true
        case nt.Expr.Throw:
            ret true
        else:
            ret false
        ..
    case nt.Stmt.Body:
        for i := 0 to value.statements.count():
            if try statementAlwaysReturns(try value.statements.get(i)):
                ret true
            ..
        ..
        ret false
    case nt.Stmt.Match:
        if value.elseBody == none:
            ret false
        ..
        if not (try statementAlwaysReturns(value.elseBody)):
            ret false
        ..
        for i := 0 to value.cases.count():
            item := try value.cases.get(i)
            if not (try statementAlwaysReturns(item.body)):
                ret false
            ..
        ..
        ret true
    case nt.Stmt.Loop:
        match value.condition as literalExpression:
        case nt.Expr.Literal:
            literal := nt.loadLiteralNode(literalExpression.literal)
            match literal as booleanLiteral:
            case nt.Literal.Boolean:
                if booleanLiteral.value && not (try statementContainsBreak(value.body)):
                    ret true
                ..
            else:
                literal = literal
            ..
        else:
        ..
        ret false
    case nt.Stmt.If:
        ret (try statementAlwaysReturns(value.body)) && (try statementAlwaysReturns(value.next))
    case nt.Stmt.Elif:
        ret (try statementAlwaysReturns(value.body)) && (try statementAlwaysReturns(value.next))
    case nt.Stmt.Else:
        ret try statementAlwaysReturns(value.body)
    case nt.Stmt.Unsafe:
        ret try statementAlwaysReturns(value.body)
    case nt.Stmt.Bounded:
        ret try statementAlwaysReturns(value.body)
    else:
        ret false
    ..
..

statementContainsBreak(statement nt.Stmt*) !bool:
    if statement == none:
        ret false
    ..
    match statement as value:
    case nt.Stmt.Break:
        ret true
    case nt.Stmt.Body:
        for i := 0 to value.statements.count():
            if try statementContainsBreak(value.statements.get(i)):
                ret true
            ..
        ..
        ret false
    case nt.Stmt.If:
        ret (try statementContainsBreak(value.body)) || (try statementContainsBreak(value.next))
    case nt.Stmt.Elif:
        ret (try statementContainsBreak(value.body)) || (try statementContainsBreak(value.next))
    case nt.Stmt.Else:
        ret try statementContainsBreak(value.body)
    case nt.Stmt.Unsafe:
        ret try statementContainsBreak(value.body)
    case nt.Stmt.Bounded:
        ret try statementContainsBreak(value.body)
    case nt.Stmt.Match:
        if try statementContainsBreak(value.elseBody):
            ret true
        ..
        for i := 0 to value.cases.count():
            if try statementContainsBreak((try value.cases.get(i)).body):
                ret true
            ..
        ..
        ret false
    else:
        # A break inside a nested loop exits that nested loop only.
        ret false
    ..
..

checkFunction(c Checker*, header nt.Header*, returnType nt.Type*, body nt.Stmt*) !void:
    declaration := header.decl
    if declaration == none:
        declaration = try c.module.getDeclFromName(header.name)
        header.decl = declaration
    ..
    if header.scope != none:
        context, contextError := header.scope.getDeclFromName("ctx")
        if contextError.ok() && context.isImplicitContext:
            declaration.implicitContextDecl = context
            sourceFile := try fileForScope(c, header.scope)
            if sourceFile.importAlias.contains("__magma_internal_context"):
                try checkType(c, context.declType, header.scope, false)
                declaration.implicitContextNeedsSlot = true
            ..
        ..
    ..
    kind := addrof declaration.kind
    match kind as function:
    case dclr.DeclKind.Function:
        if function.args.count() != header.fields.count():
            throw "function declaration argument count does not match its header"
        ..
    else:
        throw "function header is linked to a non-function declaration"
    ..
    try checkType(c, returnType, header.scope, true)
    if c.checkingSpecialization:
        returnType = try substituteType(c, returnType)
    ..
    for i := 0 to header.fields.count():
        field := try header.fields.get(i)
        match field as argument:
        case nt.Expr.VarDef:
            try checkType(c, argument.type, header.scope, false)
            if argument.decl != none && not c.checkingSpecialization:
                argument.decl.declType = argument.type
            ..
            argumentType := argument.type
            if c.checkingSpecialization:
                argumentType = try substituteType(c, argumentType)
                specializedArgument := try makeNodeExpression(c, nt.Expr.VarDef(type=argumentType, name=argument.name, decl=argument.decl, boundedCount=argument.boundedCount, sourcePos=argument.sourcePos))
                try header.fields.set(i, specializedArgument)
            ..
            if isVoidType(argumentType) || isThrowingType(argumentType):
                throw "function arguments cannot have void or throwing types"
            ..
            if argument.boundedCount != "" && not isPointerType(argumentType):
                throw "bounded parameters must be pointers"
            ..
        else:
            throw "function argument must be a typed declaration"
        ..
    ..
    previousReturn := c.returnType
    c.returnType = returnType
    functionKind := declaration.kind
    match functionKind as function:
    case dclr.DeclKind.Function:
        if body != none && (function.typeParams.count() == 0 || c.checkingSpecialization):
            try checkBody(c, body)
            if not isVoidType(returnType) && not isThrowingVoidType(returnType) && not (try statementAlwaysReturns(body)):
                throw "non-void function may fall through without returning a value"
            ..
        ..
    else:
        throw "function declaration changed kind during checking"
    ..
    c.returnType = previousReturn
    if not c.checkingSpecialization:
        declaration.semanticState = 2
    ..
..

checkStruct(c Checker*, declaration dclr.Decl*, header nt.Header*, implements nt.NodeArray[nt.Type*]) !void:
    for i := 0 to header.fields.count():
        field := try header.fields.get(i)
        match field as member:
        case nt.Expr.VarDef:
            if member.decl != none:
                member.decl.fieldIndex = i
            ..
            try checkType(c, member.type, header.scope, false)
            if isVoidType(member.type) || isThrowingType(member.type):
                throw "struct fields cannot have void or throwing types"
            ..
        else:
            throw "struct fields must be typed declarations"
        ..
    ..
    activeLayout := dclr.emptyDeclArray()
    try validateStructLayout(c, declaration, addrof activeLayout, 0)
    try checkImplementations(c, declaration, implements, header.scope)
..

validateStructLayoutType(c Checker*, type nt.Type*, active dclr.DeclArray*, depth u64) !void:
    if type == none || depth > 64:
        ret
    ..
    canonical := try canonicalType(type, 0)
    match canonical as value:
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as kind:
            case dclr.DeclKind.Struct:
                try validateStructLayout(c, value.decl, active, depth + 1)
            else:
                ret
            ..
        ..
    case nt.Type.Templated:
        owner := try typeDeclaration(c, value.owner)
        match owner.kind as kind:
        case dclr.DeclKind.Struct:
            try validateStructLayout(c, owner, active, depth + 1)
        else:
            ret
        ..
    else:
        # Pointer, owned, slice, and function fields do not inline the
        # referenced struct's storage.
        ret
    ..
..

validateStructLayout(c Checker*, declaration dclr.Decl*, active dclr.DeclArray*, depth u64) !void:
    if depth > 64:
        throw "recursive value struct layout"
    ..
    for i := 0 to active.count():
        if try active.get(i) == declaration:
            throw "recursive value struct layout"
        ..
    ..
    baseCount := active.count()
    defer restoreDeclCount(active, baseCount)
    try active.pushRight(ctx.alloc, declaration)
    match declaration.kind as kind:
    case dclr.DeclKind.Struct:
        for i := 0 to kind.fields.count():
            field := try kind.fields.get(i)
            fieldKind := field.kind
            match fieldKind as value:
            case dclr.DeclKind.Field:
                try validateStructLayoutType(c, value.type, active, depth + 1)
            else:
                ret
            ..
        ..
    else:
        ret
    ..
..

restoreDeclCount(active dclr.DeclArray*, count u64) void:
    active.length = count
..

checkImplementations(c Checker*, owner dclr.Decl*, implementations nt.NodeArray[nt.Type*], scope dclr.Scope*) !void:
    ownerName str = ""
    match owner.kind as ownerKind:
    case dclr.DeclKind.Struct:
        ownerName = ownerKind.name
    case dclr.DeclKind.Union:
        ownerName = ownerKind.name
    else:
        throw "prototype implementations require a struct or union owner"
    ..
    for i := 0 to implementations.count():
        implementation := try implementations.get(i)
        try checkType(c, implementation, scope, false)
        implementedDecl := try typeDeclaration(c, implementation)
        implementedKind := implementedDecl.kind
        match implementedKind as proto:
        case dclr.DeclKind.Proto:
            resolvedMethods := dclr.emptyDeclArray()
            for j := 0 to proto.methods.count():
                required := try proto.methods.get(j)
                requiredKind := required.kind
                match requiredKind as requiredFunction:
                case dclr.DeclKind.Function:
                    prefix := try strgs.concat(proto.name, ".")
                    defer prefix.free()
                    methodName := try strgs.trimPrefix(requiredFunction.name, prefix)
                    defer methodName.free()
                    qualifiedPrefix := try strgs.concat(ownerName, ".")
                    defer qualifiedPrefix.free()
                    qualifiedName := try strgs.concat(qualifiedPrefix, methodName)
                    defer qualifiedName.free()
                    actual := try owner.module.getDeclFromName(qualifiedName)
                    actualKind := actual.kind
                    match actualKind as actualFunction:
                    case dclr.DeclKind.Function:
                        expectedType := try typeOfDecl(c, required, required.sourceHeader.scope)
                        actualScope dclr.Scope* = none
                        if actual.sourceHeader != none:
                            actualScope = actual.sourceHeader.scope
                        ..
                        actualType := try typeOfDecl(c, actual, actualScope)
                        if not (try sameType(expectedType, actualType, 0)):
                            throw "implemented method signature does not match its prototype"
                        ..
                        try resolvedMethods.pushRight(ctx.alloc, actual)
                    else:
                        throw "prototype method name is implemented by a non-function"
                    ..
                else:
                    throw "prototype contains a non-function method"
                ..
            ..
            try owner.protoImplementations.pushRight(ctx.alloc, dclr.ProtoImplementation(prototype=implementedDecl, methods=move resolvedMethods))
        else:
            throw "implemented type must be a prototype"
        ..
    ..
..

checkGlobal(c Checker*, statement nt.GlobalStmt*) !void:
    match statement as value:
    case nt.GlobalStmt.Struct:
        try checkStruct(c, value.header.decl, value.header, value.implements)
    case nt.GlobalStmt.Function:
        try checkFunction(c, value.header, value.retType, value.body)
    case nt.GlobalStmt.ExternalFunction:
        try checkFunction(c, value.header, value.retType, none)
    case nt.GlobalStmt.Variable:
        declaration := try c.module.getDecl(value.id)
        declaration.isModuleVariable = true
        value.type = try checkVariableDeclaration(c, declaration, none)
    case nt.GlobalStmt.Alias:
        declaration := try c.module.getDecl(value.id)
        try checkType(c, value.type, none, false)
        declaration.declType = value.type
        declaration.semanticState = 2
    case nt.GlobalStmt.Method:
        ownerType := value.ownerType
        try checkType(c, ownerType, none, false)
        match value.methodBody as function:
        case nt.GlobalStmt.Function:
            try checkFunction(c, function.header, function.retType, function.body)
        else:
            throw "method body must be a function"
        ..
    case nt.GlobalStmt.Union:
        for i := 0 to value.variants.count():
            variant := try value.variants.get(i)
            if variant.decl == none:
                throw "union variant has no declaration"
            ..
            variant.decl.unionOwner = try c.module.getDecl(value.id)
            variant.decl.unionTag = i
            for j := 0 to variant.fields.count():
                field := try variant.fields.get(j)
                match field as member:
                case nt.Expr.VarDef:
                    if member.decl != none:
                        member.decl.fieldIndex = j
                    ..
                    try checkType(c, member.type, variant.scope, false)
                    if isVoidType(member.type) || isThrowingType(member.type):
                        throw "union fields cannot have void or throwing types"
                    ..
                else:
                    throw "union variant fields must be typed declarations"
                ..
            ..
        ..
        unionDecl := try c.module.getDecl(value.id)
        try checkImplementations(c, unionDecl, value.implements, value.scope)
    case nt.GlobalStmt.Enum:
        try checkType(c, value.backing, value.scope, false)
        if not isIntegerType(value.backing):
            throw "enum backing type must be an integer"
        ..
        for i := 0 to value.variants.count():
            variant := try value.variants.get(i)
            match variant as enumValue:
            case nt.Expr.VarDefAssign:
                if enumValue.decl == none:
                    throw "enum variant has no declaration"
                ..
                enumValue.decl.enumIndex = i
                enumValue.decl.enumInitializer = enumValue.assignment
                valueType := try checkExpression(c, enumValue.assignment, value.scope)
                valueType = try applyNumericContext(c, enumValue.assignment, value.backing, valueType)
                if not (try isCompatible(c, value.backing, valueType)):
                    throw "enum value has an incompatible backing type"
                ..
            case nt.Expr.VarDef:
                if enumValue.decl == none:
                    throw "enum variant has no declaration"
                ..
                enumValue.decl.enumIndex = i
                enumValue.decl.enumInitializer = none
            else:
                throw "enum contains an invalid value declaration"
            ..
        ..
    case nt.GlobalStmt.Proto:
        vtableField, vtableError := value.scope.getDeclFromName("vtable")
        if vtableError.ok():
            vtableField.fieldIndex = 0
        ..
        for i := 0 to value.methods.count():
            method := try value.methods.get(i)
            if method.decl == none:
                throw "prototype method has no declaration"
            ..
            method.decl.methodNoContext = method.noContext
            method.decl.protoMethodIndex = i
        ..
        for i := 0 to value.implements.count():
            try checkType(c, value.implements.get(i), value.scope, false)
        ..
        for i := 0 to value.methods.count():
            method := try value.methods.get(i)
            try checkFunction(c, method.header, method.returnType, none)
        ..
    case nt.GlobalStmt.LLVM:
        ret
    case nt.GlobalStmt.Embed:
        ret
    ..
..

globalDeclaration(c Checker*, statement nt.GlobalStmt*) !dclr.Decl*:
    match statement as value:
    case nt.GlobalStmt.Struct:
        ret value.header.decl
    case nt.GlobalStmt.Function:
        ret value.header.decl
    case nt.GlobalStmt.ExternalFunction:
        ret value.header.decl
    case nt.GlobalStmt.Method:
        match value.methodBody as function:
        case nt.GlobalStmt.Function:
            ret function.header.decl
        else:
            ret none
        ..
    case nt.GlobalStmt.Variable:
        ret try c.module.getDecl(value.id)
    case nt.GlobalStmt.Alias:
        ret try c.module.getDecl(value.id)
    case nt.GlobalStmt.Union:
        ret try c.module.getDecl(value.id)
    case nt.GlobalStmt.Enum:
        ret try c.module.getDecl(value.id)
    case nt.GlobalStmt.Proto:
        ret try c.module.getDecl(value.id)
    else:
        ret none
    ..
..

recordCheckFailure(c Checker*, failure error, declaration dclr.Decl*) !void:
    # Semantic failures are opaque compiler failures today. Preserve unexpected
    # runtime and allocation errors as fatal, while accumulating checker errors.
    if failure.code() != errs.ERR_FAIL:
        throw failure
    ..
    position := org.FilePos(line=0, column=0)
    code str = "TYPE_CHECK"
    hasCallSite := c.hasCallDiagnostic
    isCallArgumentTypeError := failure.message() == "call argument type is incompatible with the function signature" && hasCallSite
    relatedFile fctx.FileCtx* = none
    relatedPos := org.FilePos(line=0, column=0)
    if declaration != none:
        position = declaration.sourcePos
    ..
    if c.hasFailurePos:
        position = c.failurePos
    ..
    if hasCallSite:
        position = c.callDiagnosticPos
        relatedFile = c.callSignatureFile
        relatedPos = c.callSignaturePos
        if isCallArgumentTypeError:
            code = "CALL_ARGUMENT_TYPE"
        else:
            code = "CALL_SITE_TYPE"
        ..
    ..
    try c.errors.pushRight(comperr.CompErr(
        file=c.file,
        org=org.Origin(filePath=c.file.path, position=position),
        relatedFile=relatedFile,
        relatedPos=relatedPos,
        code=code,
        msg=failure.message(),
        help="",
        sev=comperr.Severity.ERROR,
    ))
    c.hasCallDiagnostic = false
    c.hasFailurePos = false
..

checkRoot(c Checker*, root nt.Root*) !void:
    for i := 0 to root.statements.count():
        c.returnType = none
        c.loopDepth = 0
        c.deferDepth = 0
        statement := try root.statements.get(i)
        failure := checkGlobal(c, statement)
        c.returnType = none
        c.loopDepth = 0
        c.deferDepth = 0
        if failure.nok():
            declaration := try globalDeclaration(c, statement)
            if declaration != none && declaration.semanticState == 1:
                match declaration.kind as failedDeclaration:
                case dclr.DeclKind.Variable:
                    declaration.semanticState = 0
                else:
                ..
            ..
            try recordCheckFailure(c, failure, declaration)
        ..
    ..
..

checkSpecialization(c Checker*, specialization nt.Specialization*) !void:
    if specialization.state != 0:
        ret
    ..
    specialization.state = 1
    declaration := specialization.template
    c.file = try gl.files.get(declaration.module.path)
    c.module = declaration.module
    parameters := try genericParams(declaration)
    if parameters.count() != specialization.typeArgs.count():
        throw "specialization type arguments do not match the template"
    ..
    baseCount := c.bindingParams.count()
    defer restoreBindingCount(c, baseCount)
    for i := 0 to parameters.count():
        try pushTypeBinding(c, parameters.get(i), specialization.typeArgs.get(i))
    ..
    specialization.concreteHeader = try cloneHeader(c, declaration.sourceHeader)
    specialization.concreteBody = try cloneStatement(c, declaration.sourceBody)
    c.checkingSpecialization = true
    if specialization.isFunction:
        if specialization.concreteHeader == none:
            throw "generic function has no parsed source header"
        ..
        kind := declaration.kind
        match kind as function:
        case dclr.DeclKind.Function:
            try checkFunction(c, specialization.concreteHeader, cloneType(c, function.returnType), specialization.concreteBody)
        else:
            throw "function specialization points to a non-function"
        ..
    else:
        if specialization.concreteHeader == none:
            throw "generic struct has no parsed source header"
        ..
        header := specialization.concreteHeader
        for i := 0 to header.fields.count():
            match try header.fields.get(i) as member:
            case nt.Expr.VarDef:
                try checkType(c, member.type, header.scope, false)
                member.type = try substituteType(c, member.type)
                fieldClone := try makeNodeExpression(c, nt.Expr.VarDef(type=member.type, name=member.name, decl=member.decl, boundedCount=member.boundedCount, sourcePos=member.sourcePos))
                try header.fields.set(i, fieldClone)
                if isVoidType(member.type) || isThrowingType(member.type):
                    throw "struct fields cannot have void or throwing types"
                ..
            else:
                throw "struct fields must be typed declarations"
            ..
        ..
    ..
    c.checkingSpecialization = false
    specialization.state = 2
..

pub runGraph(files fctx.FileArray) !error:
    if files.count() == 0:
        ret errs.ok()
    ..
    corePath := try path.join([]str(gl.stdLibRoot, "core.mg"))
    defer corePath.free()
    coreModule := try dclr.getModuleFromPath(corePath)

    checker := Checker(
        file=try files.get(0),
        module=(try files.get(0)).module,
        coreModule=coreModule,
        returnType=none,
        loopDepth=0,
        deferDepth=0,
        tryDepth=0,
        bindingParams=dclr.emptyDeclArray(),
        bindingTypes=nt.emptyTypePointerArray(),
        specializations=nt.emptySpecializationArray(),
        errors=try ls.new[comperr.CompErr](ctx.alloc, none),
        checkingSpecialization=false,
        unsafeDepth=0,
        callDiagnosticPos=org.FilePos(line=0, column=0),
        callSignaturePos=org.FilePos(line=0, column=0),
        callSignatureFile=none,
        hasCallDiagnostic=false,
        failurePos=org.FilePos(line=0, column=0),
        hasFailurePos=false,
    )
    for i := 0 to files.count():
        file := try files.get(i)
        checker.file = file
        checker.module = file.module
        checkStart := time.ticks()
        try checkRoot(addrof checker, addrof file.astRoot)
        file.checkingUs = time.elapsedUs(checkStart)
    ..
    nextSpecialization u64 = 0
    loop nextSpecialization < checker.specializations.count():
        specialization := try checker.specializations.get(nextSpecialization)
        nextSpecialization = nextSpecialization + 1
        specializationStart := time.ticks()
        failure := checkSpecialization(addrof checker, specialization)
        specializationFile := try gl.files.get(specialization.template.module.path)
        specializationFile.checkingUs = specializationFile.checkingUs + time.elapsedUs(specializationStart)
        if failure.nok():
            specialization.state = 3
            checker.file = try gl.files.get(specialization.template.module.path)
            checker.module = specialization.template.module
            checker.checkingSpecialization = false
            checker.returnType = none
            checker.loopDepth = 0
            checker.deferDepth = 0
            try recordCheckFailure(addrof checker, failure, specialization.template)
        ..
    ..
    if checker.errors.count() != 0:
        for i := 0 to checker.errors.count():
            diagnostic := try checker.errors.get(i)
            diagnostic.log()
        ..
        firstDiagnostic := try checker.errors.get(0)
        message := try strgs.concat("type checking failed: ", firstDiagnostic.file.path)
        defer message.free()
        line := try strconv.formatUint(firstDiagnostic.org.position.line + 1)
        defer line.free()
        withLine := try strgs.concat(message, ":l")
        defer withLine.free()
        numbered := try strgs.concat(withLine, line)
        defer numbered.free()
        detail := try strgs.concat(numbered, ": ")
        defer detail.free()
        ret errs.failure(try strgs.concat(detail, firstDiagnostic.msg))
    ..
    ret errs.ok()
..

pub run(file fctx.FileCtx*) !error:
    files := fctx.emptyFileArray()
    try files.pushRight(ctx.alloc, file)
    ret try runGraph(files)
..
