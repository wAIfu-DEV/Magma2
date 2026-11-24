mod llvm_lowering

# LLVM type and symbol spelling for the checked Magma AST. Function bodies are
# emitted by the expression/control-flow lowering routines built on this file.

use "std:hash" hash
use "std:strings" strings
use "std:strconv" strconv
use "std:builder" builder
use "std:fs" fs
use "std:cast" cast
use "std:slices" slices
use "std:list" ls
use "std:utf8" utf8
use "shared/filectx" fctx
use "shared/token_types" tokens
use "shared/global" gl

use "shared/node_types" nt
use "decl_resolver" dclr
use "link_checker" checker


freeLoweredArgument(value $str) void:
    value.free()
..

loweredConcreteType(state LoweringState*, type nt.Type*) !$nt.Type*:
    if type == none:
        throw "missing checked type in LLVM specialization lowering"
    ..
    match type as value:
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as kind:
            case dclr.DeclKind.TypeParameter:
                for i := 0 to state.genericTypeParams.count():
                    parameter := try state.genericTypeParams.get(i)
                    if parameter == value.decl:
                        if i >= state.genericTypeArgs.count():
                            throw "generic lowering state has fewer types than parameters"
                        ..
                        ret try state.genericTypeArgs.get(i)
                    ..
                ..
                throw "generic type parameter is absent from the lowering specialization"
            else:
                ret type
            ..
        ..
        ret type
    case nt.Type.Pointer:
        inner := try loweredConcreteType(state, value.toType)
        if inner == value.toType:
            ret type
        ..
        ret try storeLoweredType(nt.Type.Pointer(toType=inner))
    case nt.Type.Slice:
        inner := try loweredConcreteType(state, value.ofType)
        if inner == value.ofType:
            ret type
        ..
        ret try storeLoweredType(nt.Type.Slice(ofType=inner))
    case nt.Type.Owned:
        inner := try loweredConcreteType(state, value.ofType)
        if inner == value.ofType:
            ret type
        ..
        ret try storeLoweredType(nt.Type.Owned(ofType=inner))
    case nt.Type.Throwing:
        inner := try loweredConcreteType(state, value.ofType)
        if inner == value.ofType:
            ret type
        ..
        ret try storeLoweredType(nt.Type.Throwing(ofType=inner))
    case nt.Type.Templated:
        args := nt.emptyTypeArray()
        # The owner identifies the generic declaration. Only its arguments
        # participate in substitution; rewriting the owner can turn a valid
        # application into an invalid type node.
        changed := false
        for i := 0 to value.args.count():
            argument := try value.args.get(i)
            concrete := try loweredConcreteType(state, argument)
            changed = changed || concrete != argument
            try args.pushRight(ctx.alloc, concrete)
        ..
        if not changed:
            ret type
        ..
        ret try storeLoweredType(nt.Type.Templated(owner=value.owner, args=move args))
    case nt.Type.Function:
        args := nt.emptyTypeArray()
        changed := false
        for i := 0 to value.args.count():
            argument := try value.args.get(i)
            concrete := try loweredConcreteType(state, argument)
            changed = changed || concrete != argument
            try args.pushRight(ctx.alloc, concrete)
        ..
        concreteReturn := try loweredConcreteType(state, value.returnType)
        changed = changed || concreteReturn != value.returnType
        if not changed:
            ret type
        ..
        ret try storeLoweredType(nt.Type.Function(args=move args, returnType=concreteReturn, noContext=value.noContext))
    else:
        ret type
    ..
..

storeLoweredType(value nt.Type) !nt.Type*:
    storage := try ctx.alloc.alloc(sizeof nt.Type)
    concrete := cast.reinterpret[nt.Type](storage)
    unsafe:
        *concrete = value
    ..
    ret concrete
..

pushLoweredArgument(values ls.List[str]*, argument $str) !bool:
    try values.pushRight(move argument)
    ret true
..

lowerCallArguments(state LoweringState*, args nt.NodeArray[nt.Expr*]) !$ls.List[str]:
    values := try ls.new[str](ctx.alloc, freeLoweredArgument)
    for i := 0 to args.count():
        argumentExpr nt.Expr*, getError error = args.get(i)
        if getError.nok():
            values.free()
            throw getError
        ..
        argument str, emitError error = emitExpr(state, argumentExpr)
        if emitError.nok():
            values.free()
            throw emitError
        ..
        pushed bool, pushError error = pushLoweredArgument(addrof values, move argument)
        if pushError.nok():
            values.free()
            throw pushError
        ..
    ..
    ret move values
..

namedIdentity(declaration dclr.Decl*) !$str:
    moduleHash := try strconv.formatUint(hash.string(declaration.module.path))
    defer moduleHash.free()
    declarationName str
    match declaration.kind as kind:
    case dclr.DeclKind.Module:
        declarationName = kind.name
    case dclr.DeclKind.Variable:
        declarationName = kind.name
    case dclr.DeclKind.Argument:
        declarationName = kind.name
    case dclr.DeclKind.Field:
        declarationName = kind.name
    case dclr.DeclKind.Function:
        declarationName = kind.name
    case dclr.DeclKind.Struct:
        declarationName = kind.name
    case dclr.DeclKind.Alias:
        declarationName = kind.name
    case dclr.DeclKind.Union:
        declarationName = kind.name
    case dclr.DeclKind.Enum:
        declarationName = kind.name
    case dclr.DeclKind.Proto:
        declarationName = kind.name
    case dclr.DeclKind.UnionVariant:
        declarationName = kind.name
    case dclr.DeclKind.EnumVariant:
        declarationName = kind.name
    case dclr.DeclKind.TypeParameter:
        declarationName = kind.name
    ..
    prefix := try strings.concat("m", moduleHash)
    defer prefix.free()
    separated := try strings.concat(prefix, "_")
    defer separated.free()
    ret try strings.concat(separated, declarationName)
..

pub symbolName(declaration dclr.Decl*) !$str:
    ret try namedIdentity(declaration)
..

# LLVM type layouts need declaration identity, not just the source spelling.
# A union variant and a top-level type may share a name in the same module.
typeIdentity(declaration dclr.Decl*) !$str:
    base := try namedIdentity(declaration)
    defer base.free()
    id := try strconv.formatUint(declaration.id)
    defer id.free()
    prefix := try strings.concat(base, "_d")
    defer prefix.free()
    ret try strings.concat(prefix, id)
..

appendNameKey(out builder.Builder*, name nt.Name*) !void:
    if name == none:
        try out.appendBorrowed("<unresolved>")
        ret
    ..
    node := nt.loadNameNode(name)
    match addrof node as value:
    case nt.Name.Simple:
        try out.appendBorrowed("S")
        try out.appendCopy(value.name)
    case nt.Name.Composite:
        try out.appendBorrowed("C")
        for i := 0 to value.names.count():
            part := try value.names.get(i)
            partLength := try strconv.formatUint(part.countBytes())
            defer partLength.free()
            try out.appendCopy(partLength)
            try out.appendBorrowed(":")
            try out.appendCopy(part)
        ..
    ..
..

appendTypeKey(out builder.Builder*, type nt.Type*, depth u64) !void:
    if type == none || depth > 128:
        throw "invalid or excessively nested generic type argument"
    ..
    node := nt.loadTypeNode(type)
    match addrof node as value:
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as declarationKind:
            case dclr.DeclKind.Alias:
                # Aliases are synonyms. Key specializations by their target
                # type so callers that use an alias and its spelled target
                # agree on the same checked specialization.
                try appendTypeKey(out, declarationKind.target, depth + 1)
            else:
                if value.decl.module == none || dclr.isImplicitCoreModule(value.decl.module):
                    try out.appendBorrowed("B")
                    lowered := try typeName(type)
                    defer lowered.free()
                    try out.appendCopy(lowered)
                else:
                    try out.appendBorrowed("N")
                    identity := try typeIdentity(value.decl)
                    defer identity.free()
                    try out.appendCopy(identity)
                ..
            ..
        else:
            try out.appendBorrowed("N")
            try appendNameKey(out, value.name)
        ..
    case nt.Type.Pointer:
        try out.appendBorrowed("P")
        try appendTypeKey(out, value.toType, depth + 1)
    case nt.Type.Templated:
        try out.appendBorrowed("T")
        try appendTypeKey(out, value.owner, depth + 1)
        for i := 0 to value.args.count():
            typeArgument := try value.args.get(i)
            try appendTypeKey(out, typeArgument, depth + 1)
            try out.appendBorrowed(";")
        ..
    case nt.Type.Slice:
        try out.appendBorrowed("L")
        try appendTypeKey(out, value.ofType, depth + 1)
    case nt.Type.Owned:
        try out.appendBorrowed("O")
        try appendTypeKey(out, value.ofType, depth + 1)
    case nt.Type.Throwing:
        try out.appendBorrowed("E")
        try appendTypeKey(out, value.ofType, depth + 1)
    case nt.Type.Function:
        try out.appendBorrowed("F")
        if value.noContext:
            try out.appendBorrowed("N")
        else:
            try out.appendBorrowed("C")
        ..
        for i := 0 to value.args.count():
            argumentType := try value.args.get(i)
            try appendTypeKey(out, argumentType, depth + 1)
            try out.appendBorrowed(";")
        ..
        try appendTypeKey(out, value.returnType, depth + 1)
    case nt.Type.CompilerKnown:
        throw "unresolved compiler-known type used in specialization identity"
    case nt.Type.Void:
        try out.appendBorrowed("V")
    ..
..

pub specializationSymbol(declaration dclr.Decl*, typeArgs nt.NodeArray[nt.Type*]) !$str:
    if declaration == none || declaration.module == none:
        throw "generic specialization has no linked declaration or module"
    ..
    base $str
    match declaration.kind as declarationKind:
    case dclr.DeclKind.Struct:
        base = try typeIdentity(declaration)
    else:
        base = try namedIdentity(declaration)
    ..
    defer base.free()
    canonical := try builder.new()
    defer canonical.free()
    try canonical.appendCopy(base)
    try canonical.appendBorrowed("_")
    for i := 0 to typeArgs.count():
        typeArgument := try typeArgs.get(i)
        try appendTypeKey(addrof canonical, typeArgument, 0)
        try canonical.appendBorrowed("_")
    ..
    canonicalText := try canonical.build()
    defer canonicalText.free()
    suffix := try strconv.formatUint(hash.string(canonicalText))
    defer suffix.free()
    resultBuilder := try builder.new()
    defer resultBuilder.free()
    try resultBuilder.appendCopy(base)
    try resultBuilder.appendBorrowed("_g")
    try resultBuilder.appendCopy(suffix)
    result := try resultBuilder.build()
    ret move result
..

loweredSpecializationSymbol(state LoweringState*, declaration dclr.Decl*, typeArgs nt.NodeArray[nt.Type*]) !$str:
    concreteArgs := nt.emptyTypeArray()
    for i := 0 to typeArgs.count():
        concrete := try loweredConcreteType(state, try typeArgs.get(i))
        try concreteArgs.pushRight(ctx.alloc, concrete)
    ..
    symbol := try specializationSymbol(declaration, concreteArgs)
    ret move symbol
..

pub typeName(type nt.Type*) !$str:
    if type == none:
        throw "cannot lower an unresolved type"
    ..
    match type as value:
    case nt.Type.Pointer:
        ret try strings.copy("ptr")
    case nt.Type.Slice:
        ret try strings.copy("%type.slice")
    case nt.Type.Owned:
        ret try typeName(value.ofType)
    case nt.Type.Throwing:
        inner := try typeName(value.ofType)
        defer inner.free()
        if strings.compare(inner, "void"):
            ret try strings.copy("{ %type.error }")
        ..
        prefix := try strings.concat("{ %type.error, ", inner)
        defer prefix.free()
        ret try strings.concat(prefix, " }")
    case nt.Type.Function:
        ret try strings.copy("ptr")
    case nt.Type.CompilerKnown:
        throw "unresolved compiler-known type reached LLVM lowering"
    case nt.Type.Void:
        ret try strings.copy("void")
    case nt.Type.Named:
        if value.primitive != nt.PrimitiveType.Unresolved:
            ret try primitiveTypeName(value.primitive)
        ..
        if value.decl == none:
            if value.name != none:
                match nt.loadNameNode(value.name) as unresolvedName:
                case nt.Name.Simple:
                    throw try strings.concat("named type has no checked primitive or linked declaration: ", unresolvedName.name)
                else:
                    throw "composite type has no linked declaration"
                ..
            ..
            throw "named type has no checked primitive or linked declaration"
        ..
        match value.decl.kind as declarationKind:
        case dclr.DeclKind.Alias:
            ret try typeName(declarationKind.target)
        case dclr.DeclKind.Enum:
            ret try typeName(declarationKind.backing)
        case dclr.DeclKind.Struct:
            identity := try typeIdentity(value.decl)
            defer identity.free()
            ret try strings.concat("%", identity)
        case dclr.DeclKind.Union:
            identity := try typeIdentity(value.decl)
            defer identity.free()
            ret try strings.concat("%", identity)
        case dclr.DeclKind.UnionVariant:
            identity := try typeIdentity(value.decl)
            defer identity.free()
            ret try strings.concat("%", identity)
        case dclr.DeclKind.Proto:
            identity := try typeIdentity(value.decl)
            defer identity.free()
            ret try strings.concat("%", identity)
        case dclr.DeclKind.Function:
            ret try strings.copy("ptr")
        case dclr.DeclKind.TypeParameter:
            throw try strings.concat("unsubstituted type parameter reached LLVM lowering: ", declarationKind.name)
        else:
            throw "declaration does not name a lowerable type"
        ..
    case nt.Type.Templated:
        ownerDecl := try structDeclaration(value.owner)
        identity := try specializationSymbol(ownerDecl, value.args)
        defer identity.free()
        ret try strings.concat("%", identity)
    else:
        throw "unsupported type node reached LLVM lowering"
    ..
..

primitiveTypeName(primitive nt.PrimitiveType) !$str:
    if primitive == nt.PrimitiveType.Pointer || primitive == nt.PrimitiveType.None: ret try strings.copy("ptr") ..
    if primitive == nt.PrimitiveType.Void: ret try strings.copy("void") ..
    if primitive == nt.PrimitiveType.Bool: ret try strings.copy("i1") ..
    if primitive == nt.PrimitiveType.I8 || primitive == nt.PrimitiveType.U8: ret try strings.copy("i8") ..
    if primitive == nt.PrimitiveType.I16 || primitive == nt.PrimitiveType.U16: ret try strings.copy("i16") ..
    if primitive == nt.PrimitiveType.I32 || primitive == nt.PrimitiveType.U32: ret try strings.copy("i32") ..
    if primitive == nt.PrimitiveType.I64 || primitive == nt.PrimitiveType.U64: ret try strings.copy("i64") ..
    if primitive == nt.PrimitiveType.I128 || primitive == nt.PrimitiveType.U128: ret try strings.copy("i128") ..
    if primitive == nt.PrimitiveType.F16: ret try strings.copy("half") ..
    if primitive == nt.PrimitiveType.F32: ret try strings.copy("float") ..
    if primitive == nt.PrimitiveType.F64: ret try strings.copy("double") ..
    if primitive == nt.PrimitiveType.F128: ret try strings.copy("fp128") ..
    if primitive == nt.PrimitiveType.String: ret try strings.copy("%type.str") ..
    if primitive == nt.PrimitiveType.Error: ret try strings.copy("%type.error") ..
    if primitive == nt.PrimitiveType.Slice: ret try strings.copy("%type.slice") ..
    throw "unresolved primitive type reached LLVM lowering"
..

DeferFrame(
    parent DeferFrame*
    deferred nt.NodeArray[nt.Stmt*]
    activeCount u64
    savedCount u64
)

loweredTypeName(state LoweringState*, type nt.Type*) !$str:
    if type == none:
        throw "lowering state received a null type"
    ..
    concrete := try loweredConcreteType(state, type)
    match type as value:
    case nt.Type.Owned:
        ret try loweredTypeName(state, value.ofType)
    case nt.Type.Throwing:
        inner := try loweredTypeName(state, value.ofType)
        defer inner.free()
        if strings.compare(inner, "void"):
            ret try strings.copy("{ %type.error }")
        ..
        prefix := try strings.concat("{ %type.error, ", inner)
        defer prefix.free()
        ret try strings.concat(prefix, " }")
    else:
        ret try typeName(concrete)
    ..
..

TypeLayout(
    size u64
    alignment u64
)

UnionVariantInfo(
    unionDecl dclr.Decl*
    tag u64
)

LoweringState(
    output builder.Builder*
    returnType nt.Type*
    nextValue u64
    nextBlock u64
    breakTarget str
    continueTarget str
    deferFrame DeferFrame*
    loopDeferBoundary DeferFrame*
    hasContext bool
    hasLocalContext bool
    localContextId u64
    currentBlock str
    matchBindingDecl dclr.Decl*
    matchBindingPointerId u64
    matchBindingPointerKind u8
    matchBindingIsPointer bool
    genericTypeArgs nt.NodeArray[nt.Type*]
    genericTypeParams dclr.DeclArray
)

setCurrentBlock(state LoweringState*, label str) !void:
    updated := try strings.copy(label)
    state.currentBlock = move updated
..

implicitContextDeclaration(declaration dclr.Decl*) !dclr.Decl*:
    if declaration == none:
        ret none
    ..
    ret declaration.implicitContextDecl
..

implicitContextTypeName(declaration dclr.Decl*) !$str:
    context := try implicitContextDeclaration(declaration)
    if context == none:
        throw "function has no implicit context binding"
    ..
    ret try typeName(context.declType)
..

appendFunctionContextSlot(out builder.Builder*, declaration dclr.Decl*, hasContext bool) !$u64:
    if hasContext:
        ret 0
    ..
    context := try implicitContextDeclaration(declaration)
    if context == none:
        ret 0
    ..
    if not declaration.implicitContextNeedsSlot:
        ret 0
    ..
    contextType := try implicitContextTypeName(declaration)
    defer contextType.free()
    id := try strconv.formatUint(context.id)
    defer id.free()
    try out.appendBorrowed("  %slot")
    try out.appendCopy(id)
    try out.appendBorrowed(" = alloca ")
    try out.appendCopy(contextType)
    try out.appendBorrowed("\n  store ")
    try out.appendCopy(contextType)
    try out.appendBorrowed(" zeroinitializer, ptr %slot")
    try out.appendCopy(id)
    try out.appendBorrowed("\n")
    ret context.id
..

appendContextPointer(out builder.Builder*, state LoweringState*) !void:
    if state.hasContext:
        try out.appendBorrowed("%ctx.in")
    elif state.hasLocalContext:
        id := try strconv.formatUint(state.localContextId)
        defer id.free()
        try out.appendBorrowed("%slot")
        try out.appendCopy(id)
    else:
        try out.appendBorrowed("@magma.context.root")
    ..
..

newLoopSlotList() !$ls.List[u64]:
    ret try ls.new[u64](ctx.alloc, none)
..

appendLocalSlotAlloca(state LoweringState*, declaration dclr.Decl*, type nt.Type*, seen ls.List[u64]*) !void:
    if declaration == none || type == none:
        ret
    ..
    for i := 0 to seen.count():
        if try seen.get(i) == declaration.id:
            ret
        ..
    ..
    try seen.pushRight(declaration.id)
    lowered := try loweredTypeName(state, type)
    defer lowered.free()
    id := try strconv.formatUint(declaration.id)
    defer id.free()
    try state.output.appendBorrowed("  %slot")
    try state.output.appendCopy(id)
    try state.output.appendBorrowed(" = alloca ")
    try state.output.appendCopy(lowered)
    try state.output.appendBorrowed("\n")
..

emitForLoopIndexAllocas(state LoweringState*, statement nt.Stmt*, seen ls.List[u64]*) !void:
    if statement == none:
        ret
    ..
    match statement as value:
    case nt.Stmt.Body:
        for i := 0 to value.statements.count():
            try emitForLoopIndexAllocas(state, try value.statements.get(i), seen)
        ..
    case nt.Stmt.If:
        try emitForLoopIndexAllocas(state, value.body, seen)
        try emitForLoopIndexAllocas(state, value.next, seen)
    case nt.Stmt.Elif:
        try emitForLoopIndexAllocas(state, value.body, seen)
        try emitForLoopIndexAllocas(state, value.next, seen)
    case nt.Stmt.Else:
        try emitForLoopIndexAllocas(state, value.body, seen)
    case nt.Stmt.Loop:
        try emitForLoopIndexAllocas(state, value.body, seen)
    case nt.Stmt.ForLoop:
        indexNode := nt.loadExpressionNode(value.index)
        match addrof indexNode as index:
        case nt.Expr.VarDefAssign:
            if index.decl == none:
                throw "for-loop index has no linked declaration"
            ..
            try appendLocalSlotAlloca(state, index.decl, index.type, seen)
        else:
            throw "for-loop index must be an initialized variable"
        ..
        try emitForLoopIndexAllocas(state, value.body, seen)
    case nt.Stmt.Defer:
        try emitForLoopIndexAllocas(state, value.body, seen)
    case nt.Stmt.OnError:
        try emitForLoopIndexAllocas(state, value.body, seen)
    case nt.Stmt.Unsafe:
        try emitForLoopIndexAllocas(state, value.body, seen)
    case nt.Stmt.Bounded:
        try emitForLoopIndexAllocas(state, value.body, seen)
    case nt.Stmt.Match:
        if value.bindingDecl != none:
            bindingType := try expressionType(value.expression)
            try appendLocalSlotAlloca(state, value.bindingDecl, bindingType, seen)
        ..
        for i := 0 to value.cases.count():
            item := try value.cases.get(i)
            try emitForLoopIndexAllocas(state, item.body, seen)
        ..
        try emitForLoopIndexAllocas(state, value.elseBody, seen)
    case nt.Stmt.Expression:
        expressionNode := nt.loadExpressionNode(value.expr)
        match addrof expressionNode as expressionValue:
        case nt.Expr.VarDef:
            try appendLocalSlotAlloca(state, expressionValue.decl, expressionValue.type, seen)
        case nt.Expr.VarDefAssign:
            if expressionValue.type == none:
                throw "initialized variable has no checked type during slot allocation"
            ..
            try appendLocalSlotAlloca(state, expressionValue.decl, expressionValue.type, seen)
        case nt.Expr.VarDefAssignDestructure:
            callType := try expressionType(expressionValue.call)
            innerType := try throwingValueType(callType)
            if expressionValue.valueDecl != none:
                try appendLocalSlotAlloca(state, expressionValue.valueDecl, innerType, seen)
            ..
            if expressionValue.errorDecl != none:
                try appendLocalSlotAlloca(state, expressionValue.errorDecl, expressionValue.errorDecl.declType, seen)
            ..
        else:
            expressionNode = expressionNode
        ..
    else:
        ret
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

isThrowingVoidType(type nt.Type*) !bool:
    if type == none: ret false ..
    match type as value:
    case nt.Type.Throwing:
        ret try isVoidType(value.ofType)
    else:
        ret false
    ..
..

sameDeclarationIdentity(left dclr.Decl*, right dclr.Decl*) bool:
    if left == right: ret true ..
    if left == none || right == none: ret false ..
    if left.id == right.id:
        if left.module == none || right.module == none: ret false ..
        if left.module == right.module: ret true ..
        if strings.compare(left.module.path, right.module.path): ret true ..
    ..
    ret false
..

throwingValueType(type nt.Type*) !nt.Type*:
    match type as value:
    case nt.Type.Throwing:
        ret value.ofType
    else:
        throw "throwing operation is inside a non-throwing function"
    ..
..

isVoidType(type nt.Type*) !bool:
    lowered := try typeName(type)
    defer lowered.free()
    ret strings.compare(lowered, "void")
..

expressionType(expression nt.Expr*) !nt.Type*:
    node := nt.loadExpressionNode(expression)
    match addrof node as value:
    case nt.Expr.Literal:
        if value.type == none: throw "literal has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Named:
        if value.type == none: throw "named expression has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.MemberAccess:
        if value.type == none: throw "member access has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Subscript:
        if value.type == none: throw "subscript has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Array:
        if value.type == none: throw "array expression has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.InlineLLVM:
        if value.type == none: throw "inline LLVM expression has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.VarDef:
        if value.type == none: throw "variable definition has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.VarDefAssign:
        if value.type == none: throw "variable assignment has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Sizeof:
        if value.type == none: throw "sizeof expression has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Unary:
        if value.type == none: throw "unary expression has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Move:
        if value.type == none: throw "move expression has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Binary:
        if value.type == none: throw "binary expression has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.DirectCall:
        if value.type == none: throw "direct call has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.TemplatedDirectCall:
        if value.type == none: throw "templated direct call has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.IndirectCall:
        if value.type == none: throw "indirect call has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.TemplatedIndirectCall:
        if value.type == none: throw "templated indirect call has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Try:
        if value.type == none: throw "try expression has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.GenericApply:
        if value.type == none: throw "generic application has no checked type in LLVM lowering" ..
        ret value.type
    case nt.Expr.Assign:
        if value.type == none: throw "assignment has no checked type in LLVM lowering" ..
        ret value.type
    else: throw "expression does not have a lowered value type"
    ..
..

appendType(out builder.Builder*, type nt.Type*) !void:
    lowered := try typeName(type)
    defer lowered.free()
    try out.appendCopy(lowered)
..

stringGlobalName(value str) !$str:
    digest := try strconv.formatUint(hash.string(value))
    defer digest.free()
    prefix := try strings.concat(".magma.str.", digest)
    ret move prefix
..

llvmHexDigit(value u8) u8:
    if value < 10:
        ret value + 48
    ..
    ret value - 10 + 65
..

appendLLVMBytes(out builder.Builder*, value str) !void:
    for i := 0 to value.countBytes():
        byte := strings.byteAt(value, i)
        if byte >= 32 && byte <= 126 && byte != 34 && byte != 92:
            try out.addByte(byte)
        else:
            try out.addByte(92)
            try out.addByte(llvmHexDigit(byte >> 4))
            try out.addByte(llvmHexDigit(byte & 15))
        ..
    ..
..

emitStringGlobals(out builder.Builder*, file fctx.FileCtx*) !void:
    for i := 0 to file.tokens.count():
        token := try file.tokens.get(i)
        if token.type != tokens.TkType.LIT_STR:
            continue
        ..
        duplicate := false
        for j := 0 to i:
            prior := try file.tokens.get(j)
            if prior.type == tokens.TkType.LIT_STR && strings.compare(prior.repr, token.repr):
                duplicate = true
                break
            ..
        ..
        if duplicate:
            continue
        ..
        name := try stringGlobalName(token.repr)
        defer name.free()
        length := try strconv.formatUint(token.repr.countBytes() + 1)
        defer length.free()
        try out.appendBorrowed("@")
        try out.appendCopy(name)
        try out.appendBorrowed(" = private unnamed_addr constant [")
        try out.appendCopy(length)
        try out.appendBorrowed(" x i8] c\"")
        try appendLLVMBytes(out, token.repr)
        try out.appendBorrowed("\\00\", align 1\n")
    ..
..

appendStringConstant(out builder.Builder*, value str) !void:
    constant := try stringConstantValue(value)
    defer constant.free()
    try out.appendBorrowed("%type.str ")
    try out.appendCopy(constant)
..

stringConstantValue(value str) !$str:
    name := try stringGlobalName(value)
    defer name.free()
    length := try strconv.formatUint(value.countBytes() + 1)
    defer length.free()
    byteCount := try strconv.formatUint(value.countBytes())
    defer byteCount.free()
    first := try strings.concat("{ ptr getelementptr inbounds ([", length)
    defer first.free()
    second := try strings.concat(first, " x i8], ptr @")
    defer second.free()
    third := try strings.concat(second, name)
    defer third.free()
    fourth := try strings.concat(third, ", i64 0, i64 0), i64 ")
    defer fourth.free()
    fifth := try strings.concat(fourth, byteCount)
    defer fifth.free()
    ret try strings.concat(fifth, ", ptr null, ptr null }")
..

emitGlobalStructValue(out builder.Builder*, constructor dclr.Decl*, args nt.NodeArray[nt.Expr*]) !void:
    match constructor.kind as constructorKind:
    case dclr.DeclKind.Struct:
        try out.appendBorrowed("{")
        for globalFieldIndex := 0 to constructorKind.fields.count():
            if globalFieldIndex != 0:
                try out.appendBorrowed(", ")
            ..
            field := try constructorKind.fields.get(globalFieldIndex)
            match field.kind as structField:
            case dclr.DeclKind.Field:
                try appendType(out, structField.type)
                try out.appendBorrowed(" ")
                fieldInitializer nt.Expr* = none
                for argumentIndex := 0 to args.count():
                    initializerArgument := try args.get(argumentIndex)
                    argumentNode := nt.loadExpressionNode(initializerArgument)
                    match addrof argumentNode as argument:
                    case nt.Expr.Assign:
                        if not argument.hasResolvedFieldIndex:
                            throw "global struct constructor has an unresolved field index"
                        ..
                        if argument.resolvedFieldIndex == globalFieldIndex:
                            fieldInitializer = argument.expr
                        ..
                    else:
                        if argumentIndex == globalFieldIndex:
                            fieldInitializer = initializerArgument
                        ..
                    ..
                ..
                if fieldInitializer != none:
                    constant := try emitConstantExpression(fieldInitializer)
                    defer constant.free()
                    try out.appendCopy(constant)
                else:
                    try out.appendBorrowed("zeroinitializer")
                ..
            else:
                throw "struct constructor field has no field type"
            ..
        ..
        try out.appendBorrowed("}")
    else:
        throw "global constructor initializer must construct a struct"
    ..
..

emitGlobalArrayValue(out builder.Builder*, symbol str, array nt.Expr.Array*, args nt.NodeArray[nt.Expr*]) !void:
    if array.length == none || not array.hasResolvedLength:
        throw "global array constructor has no checked fixed length"
    ..
    length := try strconv.formatUint(array.resolvedLength)
    defer length.free()
    elementType := try typeName(array.type)
    defer elementType.free()
    backingSymbol := try strings.concat(symbol, ".storage")
    defer backingSymbol.free()
    try out.appendBorrowed("{ ptr getelementptr inbounds ([")
    try out.appendCopy(length)
    try out.appendBorrowed(" x ")
    try out.appendCopy(elementType)
    try out.appendBorrowed("], ptr @")
    try out.appendCopy(backingSymbol)
    try out.appendBorrowed(", i64 0, i64 0), i64 ")
    try out.appendCopy(length)
    try out.appendBorrowed(" }\n@")
    try out.appendCopy(backingSymbol)
    try out.appendBorrowed(" = private global [")
    try out.appendCopy(length)
    try out.appendBorrowed(" x ")
    try out.appendCopy(elementType)
    lengthValue := array.resolvedLength
    if args.count() == 0:
        try out.appendBorrowed("] zeroinitializer")
        ret
    ..
    try out.appendBorrowed("] [")
    if array.resolvedIndices.count() != args.count():
        throw "checked global array constructor has an incomplete index map"
    ..
    for i := 0 to lengthValue:
        if i != 0:
            try out.appendBorrowed(", ")
        ..
        selected nt.Expr* = none
        for j := 0 to args.count():
            candidate := try args.get(j)
            candidateNode := nt.loadExpressionNode(candidate)
            candidateValue nt.Expr* = candidate
            candidateIndex := try array.resolvedIndices.get(j)
            match addrof candidateNode as assignment:
            case nt.Expr.Assign:
                candidateValue = assignment.expr
            case nt.Expr.VarDefAssign:
                candidateValue = assignment.assignment
            else:
                candidateNode = candidateNode
            ..
            if candidateIndex == i:
                selected = candidateValue
                break
            ..
        ..
        try out.appendCopy(elementType)
        try out.appendBorrowed(" ")
        if selected == none:
            try out.appendBorrowed("zeroinitializer")
        else:
            constant := try emitConstantExpression(selected)
            defer constant.free()
            try out.appendCopy(constant)
        ..
    ..
    try out.appendBorrowed("]")
..

declarationNoContext(declaration dclr.Decl*) !bool:
    if declaration == none:
        throw "call declaration has no checked calling convention"
    ..
    ret try typeNoContext(declaration.declType)
..

declarationLinkName(declaration dclr.Decl*) !$str:
    if declaration == none:
        throw "function has no checked declaration"
    ..
    if declaration.externalName != "":
        ret try strings.copy(declaration.externalName)
    ..
    ret try symbolName(declaration)
..

methodReceiver(declaration dclr.Decl*) !dclr.Decl*:
    if declaration == none:
        throw "method has no checked declaration"
    ..
    ret declaration.receiverDecl
..

methodHasGenericOwner(declaration dclr.Decl*) !bool:
    if declaration == none:
        throw "generic method has no checked declaration"
    ..
    match declaration.methodOwnerType as ownerType:
    case nt.Type.Templated: ret true
    else: ret false
    ..
..

specializationParameters(specialization nt.Specialization*) !dclr.DeclArray:
    if specialization == none || specialization.template == none:
        throw "checked specialization has no template declaration"
    ..
    ret specialization.typeParams
..

typeNoContext(type nt.Type*) !bool:
    if type == none:
        throw "callable type is missing checked calling convention"
    ..
    match type as value:
    case nt.Type.Function:
        ret value.noContext
    case nt.Type.Pointer:
        match value.toType as pointed:
        case nt.Type.Function:
            ret pointed.noContext
        else:
            throw "indirect call target is not a checked function pointer"
        ..
    case nt.Type.Owned:
        ret try typeNoContext(value.ofType)
    case nt.Type.Named:
        if value.decl != none:
            match value.decl.kind as declarationKind:
            case dclr.DeclKind.Alias:
                ret try typeNoContext(declarationKind.target)
            else:
                throw "indirect call target has no checked function type"
            ..
        ..
        throw "indirect call target has an unresolved checked type"
    else:
        throw "indirect call target has no checked function type"
    ..
..

appendArgumentName(out builder.Builder*, declaration dclr.Decl*) !void:
    id := try strconv.formatUint(declaration.id)
    defer id.free()
    try out.appendBorrowed("%arg")
    try out.appendCopy(id)
..

emitConstantStructConstructor(declaration dclr.Decl*, args nt.NodeArray[nt.Expr*]) !$str:
    structure := declaration.kind
    fields dclr.DeclArray
    match structure as kind:
    case dclr.DeclKind.Struct:
        fields = kind.fields
    else:
        throw "constant constructor is not a structure"
    ..
    out := try builder.new()
    defer out.free()
    try out.appendBorrowed("{")
    for i := 0 to fields.count():
        fieldDecl := try fields.get(i)
        match fieldDecl.kind as field:
        case dclr.DeclKind.Field:
            if i != 0: try out.appendBorrowed(", ") ..
            selected nt.Expr* = none
            for j := 0 to args.count():
                candidate := try args.get(j)
                candidateNode := nt.loadExpressionNode(candidate)
                selectedFieldIndex := j
                match addrof candidateNode as assignment:
                case nt.Expr.Assign:
                    if not assignment.hasResolvedFieldIndex:
                        throw "constant struct constructor has an unresolved field index"
                    ..
                    selectedFieldIndex = assignment.resolvedFieldIndex
                    if selectedFieldIndex == i: selected = assignment.expr ..
                else:
                    if selectedFieldIndex == i: selected = candidate ..
                ..
            ..
            if selected == none: throw "constant structure field has no initializer" ..
            fieldType := try typeName(field.type)
            defer fieldType.free()
            constant := try emitConstantExpression(selected)
            defer constant.free()
            try out.appendCopy(fieldType)
            try out.appendBorrowed(" ")
            try out.appendCopy(constant)
        else:
            throw "constant structure contains a non-field declaration"
        ..
    ..
    try out.appendBorrowed("}")
    result := try out.build()
    ret move result
..

emitConstantExpression(expression nt.Expr*) !$str:
    node := nt.loadExpressionNode(expression)
    match addrof node as value:
    case nt.Expr.Literal:
        match value.literal as literal:
        case nt.Literal.Number:
            ret try strings.copy(literal.value)
        case nt.Literal.HexNumber:
            ret try strings.copy(literal.value)
        case nt.Literal.Boolean:
            if literal.value:
                ret try strings.copy("1")
            ..
            ret try strings.copy("0")
        case nt.Literal.Char8:
            if literal.value.countBytes() != 1:
                throw "invalid 8-bit constant character"
            ..
            ret try strconv.formatUint(cast.u8to64(strings.byteAt(literal.value, 0)))
        case nt.Literal.Char32:
            input u8[] = slices.fromPtr(strings.toPtr(literal.value), literal.value.countBytes())
            codepoint := try utf8.decode(input)
            ret try strconv.formatUint(cast.u32to64(codepoint.value))
        case nt.Literal.None:
            ret try strings.copy("null")
        case nt.Literal.String:
            ret try stringConstantValue(literal.value)
        else:
            throw "unsupported compile-time constant in LLVM lowering"
        ..
    case nt.Expr.Sizeof:
        lowered := try typeName(value.operand)
        defer lowered.free()
        prefix := try strings.concat("ptrtoint (ptr getelementptr (", lowered)
        defer prefix.free()
        ret try strings.concat(prefix, ", ptr null, i64 1) to i64)")
    case nt.Expr.CompilerKnown:
        if value.resolvedValue == "":
            throw "compiler-known constant has no checked value"
        ..
        ret try strings.copy(value.resolvedValue)
    case nt.Expr.Move:
        ret try emitConstantExpression(value.operand)
    case nt.Expr.Assign:
        ret try emitConstantExpression(value.expr)
    case nt.Expr.VarDefAssign:
        ret try emitConstantExpression(value.assignment)
    case nt.Expr.IndirectCall:
        if value.callKind == nt.CallKind.StructConstructor && value.target != none:
            ret try emitConstantStructConstructor(value.target, value.args)
        ..
        throw "global constant call has no checked struct-constructor classification"
    case nt.Expr.TemplatedIndirectCall:
        if value.callKind == nt.CallKind.StructConstructor && value.target != none:
            ret try emitConstantStructConstructor(value.target, value.args)
        ..
        throw "global templated constant call has no checked struct-constructor classification"
    case nt.Expr.Named:
        if value.decl == none:
            throw "unresolved name in compile-time constant"
        ..
        match value.decl.kind as declarationKind:
        case dclr.DeclKind.Variable:
            if declarationKind.isConst && declarationKind.initializer != none:
                ret try emitConstantExpression(declarationKind.initializer)
            ..
            if declarationKind.isGlobal || (try isModuleVariable(value.decl)):
                symbol := try symbolName(value.decl)
                defer symbol.free()
                ret try strings.concat("@", symbol)
            ..
        case dclr.DeclKind.Function:
            symbol := try declarationLinkName(value.decl)
            defer symbol.free()
            ret try strings.concat("@", symbol)
        case dclr.DeclKind.EnumVariant:
            if value.decl.enumInitializer != none:
                ret try emitConstantExpression(value.decl.enumInitializer)
            ..
            ret try strconv.formatUint(value.decl.enumIndex)
        else:
            value = value
        ..
        throw "name is not a compile-time constant"
    case nt.Expr.MemberAccess:
        declaration dclr.Decl* = none
        memberNode := nt.loadExpressionNode(value.member)
        match addrof memberNode as resolvedMember:
        case nt.Expr.Named:
            declaration = resolvedMember.decl
        else:
            throw "member constant has no checked name"
        ..
        if declaration == none:
            throw "unresolved member in compile-time constant"
        ..
        match declaration.kind as declarationKind:
        case dclr.DeclKind.Function:
            symbol := try declarationLinkName(declaration)
            defer symbol.free()
            ret try strings.concat("@", symbol)
        case dclr.DeclKind.Variable:
            if declarationKind.isGlobal || (try isModuleVariable(declaration)):
                symbol := try symbolName(declaration)
                defer symbol.free()
                ret try strings.concat("@", symbol)
            ..
        case dclr.DeclKind.EnumVariant:
            ret try enumVariantValue(declaration)
        else:
            declaration = declaration
        ..
        throw "member is not a compile-time constant"
    case nt.Expr.Subscript:
        throw "subscript expression is not a compile-time LLVM constant"
    case nt.Expr.Array:
        throw "array expression is not a compile-time LLVM constant"
    case nt.Expr.DirectCall:
        if value.callKind == nt.CallKind.StructConstructor && value.decl != none:
            ret try emitConstantStructConstructor(value.decl, value.args)
        ..
        throw "direct constant call has no checked struct-constructor classification"
    case nt.Expr.TemplatedDirectCall:
        if value.callKind == nt.CallKind.StructConstructor && value.decl != none:
            ret try emitConstantStructConstructor(value.decl, value.args)
        ..
        throw "templated direct constant call has no checked struct-constructor classification"
    case nt.Expr.GenericApply:
        throw "generic application is not a compile-time LLVM constant"
    case nt.Expr.Unary:
        throw "unary expression is not a compile-time LLVM constant"
    case nt.Expr.Binary:
        throw "binary expression is not a compile-time LLVM constant"
    else:
        throw "global initializer is not a supported LLVM constant"
    ..
..

enumVariantValue(declaration dclr.Decl*) !$str:
    if declaration == none:
        throw "enum variant has no checked declaration"
    ..
    if declaration.enumInitializer != none:
        ret try emitConstantExpression(declaration.enumInitializer)
    ..
    ret try strconv.formatUint(declaration.enumIndex)
..

emitResolvedCall(state LoweringState*, kind nt.CallKind, target dclr.Decl*, owner nt.Expr*, resultType nt.Type*, args nt.NodeArray[nt.Expr*], typeArgs nt.NodeArray[nt.Type*]) !$str:
    if kind == nt.CallKind.ProtoImpl || kind == nt.CallKind.ProtoImplBorrow:
        ret try emitProtoImplementation(state, owner, resultType)
    ..
    if kind == nt.CallKind.ProtoView || kind == nt.CallKind.ProtoViewBorrow:
        ret try emitProtoView(state, owner, resultType)
    ..
    if kind == nt.CallKind.ProtoMethod:
        ret try emitProtoMethodCall(state, owner, resultType, args)
    ..
    if kind == nt.CallKind.StaticMethod:
        ret try emitStaticMethodCall(state, owner, resultType, args, typeArgs)
    ..
    if kind == nt.CallKind.ArrayConstructor:
        arrayNode := nt.loadExpressionNode(owner)
        match addrof arrayNode as array:
        case nt.Expr.Array:
            ret try emitArrayConstructor(state, array, args)
        else:
            throw "checked array-constructor call has no array type node"
        ..
    ..
    if kind == nt.CallKind.StructConstructor:
        if target == none:
            throw "checked struct constructor has no target declaration"
        ..
        ret try emitStructConstructor(state, resultType, target, args)
    ..
    if kind == nt.CallKind.UnionConstructor:
        if target == none:
            throw "checked union constructor has no target declaration"
        ..
        ret try emitUnionVariantConstructor(state, resultType, target, args)
    ..
    if kind == nt.CallKind.FunctionCall:
        if target == none:
            throw "checked function call has no target declaration"
        ..
        if typeArgs.count() != 0:
            specialization := try loweredSpecializationSymbol(state, target, typeArgs)
            defer specialization.free()
            ret try emitCallSymbol(state, resultType, specialization, args, false, try declarationNoContext(target))
        ..
        match target.kind as functionKind:
        case dclr.DeclKind.Function:
            if functionKind.typeParams.count() != 0:
                throw "checked function call has no specialization arguments"
            ..
        else:
            throw "checked function call target is not a function"
        ..
        ret try emitCall(state, resultType, target, args)
    ..
    if kind == nt.CallKind.Indirect:
        callee := try emitExpr(state, owner)
        defer callee.free()
        ret try emitCallSymbol(state, resultType, callee, args, true, try typeNoContext(try expressionType(owner)))
    ..
    throw "call reached LLVM lowering without a checked call classification"
..

emitExpr(state LoweringState*, expression nt.Expr*) !$str:
    match expression as value:
    case nt.Expr.Literal:
        match value.literal as literal:
        case nt.Literal.Number:
            ret try strings.copy(literal.value)
        case nt.Literal.HexNumber:
            ret try strings.copy(literal.value)
        case nt.Literal.Boolean:
            if literal.value:
                ret try strings.copy("1")
            ..
            ret try strings.copy("0")
        case nt.Literal.String:
            name := try stringGlobalName(literal.value)
            defer name.free()
            arrayLength := try strconv.formatUint(literal.value.countBytes() + 1)
            defer arrayLength.free()
            byteCount := try strconv.formatUint(literal.value.countBytes())
            defer byteCount.free()
            firstId := try strconv.formatUint(state.nextValue)
            defer firstId.free()
            state.nextValue = state.nextValue + 1
            secondId := try strconv.formatUint(state.nextValue)
            defer secondId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(firstId)
            try state.output.appendBorrowed(" = insertvalue %type.str zeroinitializer, ptr getelementptr inbounds ([")
            try state.output.appendCopy(arrayLength)
            try state.output.appendBorrowed(" x i8], ptr @")
            try state.output.appendCopy(name)
            try state.output.appendBorrowed(", i64 0, i64 0), 0\n  %v")
            try state.output.appendCopy(secondId)
            try state.output.appendBorrowed(" = insertvalue %type.str %v")
            try state.output.appendCopy(firstId)
            try state.output.appendBorrowed(", i64 ")
            try state.output.appendCopy(byteCount)
            try state.output.appendBorrowed(", 1\n")
            ret try strings.concat("%v", secondId)
        case nt.Literal.Char8:
            if literal.value.countBytes() != 1:
                throw "invalid 8-bit character literal reached LLVM lowering"
            ..
            ret try strconv.formatUint(cast.u8to64(strings.byteAt(literal.value, 0)))
        case nt.Literal.Char32:
            input u8[] = slices.fromPtr(strings.toPtr(literal.value), literal.value.countBytes())
            codepoint := try utf8.decode(input)
            ret try strconv.formatUint(cast.u32to64(codepoint.value))
        case nt.Literal.None:
            ret try strings.copy("null")
        else:
            throw "unsupported literal in LLVM lowering"
        ..
    case nt.Expr.Array:
        ret try emitArrayConstructor(state, value, nt.emptyExpressionArray())
    case nt.Expr.Named:
        if value.decl == none:
            throw "unresolved name reached LLVM lowering"
        ..
        if value.decl.isImplicitContext:
            contextType := try typeName(value.type)
            defer contextType.free()
            contextId := try strconv.formatUint(state.nextValue)
            defer contextId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(contextId)
            try state.output.appendBorrowed(" = load ")
            try state.output.appendCopy(contextType)
            try state.output.appendBorrowed(", ptr ")
            if state.hasContext:
                try state.output.appendBorrowed("%ctx.in")
            elif state.hasLocalContext:
                localId := try strconv.formatUint(state.localContextId)
                defer localId.free()
                try state.output.appendBorrowed("%slot")
                try state.output.appendCopy(localId)
            else:
                throw "implicit context binding has no storage in this function"
            ..
            try state.output.appendBorrowed("\n")
            ret try strings.concat("%v", contextId)
        ..
        if sameDeclarationIdentity(state.matchBindingDecl, value.decl):
            if state.matchBindingIsPointer:
                bindingId := try strconv.formatUint(state.matchBindingPointerId)
                defer bindingId.free()
                if state.matchBindingPointerKind == 1:
                    ret try strings.concat("%v", bindingId)
                ..
                loadedPointerId := try strconv.formatUint(state.nextValue)
                defer loadedPointerId.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(loadedPointerId)
                try state.output.appendBorrowed(" = load ptr, ptr %slot")
                try state.output.appendCopy(bindingId)
                try state.output.appendBorrowed("\n")
                ret try strings.concat("%v", loadedPointerId)
            ..
            resultType := try typeName(value.type)
            defer resultType.free()
            bindingId := try strconv.formatUint(state.matchBindingPointerId)
            defer bindingId.free()
            loadedId := try strconv.formatUint(state.nextValue)
            defer loadedId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(loadedId)
            try state.output.appendBorrowed(" = load ")
            try state.output.appendCopy(resultType)
            try state.output.appendBorrowed(", ptr ")
            if state.matchBindingPointerKind == 1:
                try state.output.appendBorrowed("%v")
            else:
                try state.output.appendBorrowed("%slot")
            ..
            try state.output.appendCopy(bindingId)
            try state.output.appendBorrowed("\n")
            ret try strings.concat("%v", loadedId)
        ..
        match value.decl.kind as declarationKind:
        case dclr.DeclKind.Argument:
            argumentId := try strconv.formatUint(value.decl.id)
            defer argumentId.free()
            argumentType := try typeName(value.type)
            defer argumentType.free()
            loadedId := try strconv.formatUint(state.nextValue)
            defer loadedId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(loadedId)
            try state.output.appendBorrowed(" = load ")
            try state.output.appendCopy(argumentType)
            try state.output.appendBorrowed(", ptr %slot")
            try state.output.appendCopy(argumentId)
            try state.output.appendBorrowed("\n")
            ret try strings.concat("%v", loadedId)
        case dclr.DeclKind.Variable:
            if declarationKind.isConst && declarationKind.initializer != none:
                ret try emitConstantExpression(declarationKind.initializer)
            ..
            if declarationKind.isGlobal || (try isModuleVariable(value.decl)):
                symbol := try symbolName(value.decl)
                defer symbol.free()
                loadedType := try typeName(value.type)
                defer loadedType.free()
                tempId := try strconv.formatUint(state.nextValue)
                defer tempId.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(tempId)
                try state.output.appendBorrowed(" = load ")
                try state.output.appendCopy(loadedType)
                try state.output.appendBorrowed(", ptr @")
                try state.output.appendCopy(symbol)
                try state.output.appendBorrowed("\n")
                ret try strings.concat("%v", tempId)
            ..
            localId := try strconv.formatUint(value.decl.id)
            defer localId.free()
            localType := try typeName(value.type)
            defer localType.free()
            loadedId := try strconv.formatUint(state.nextValue)
            defer loadedId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(loadedId)
            try state.output.appendBorrowed(" = load ")
            try state.output.appendCopy(localType)
            try state.output.appendBorrowed(", ptr %slot")
            try state.output.appendCopy(localId)
            try state.output.appendBorrowed("\n")
            ret try strings.concat("%v", loadedId)
        case dclr.DeclKind.Function:
            symbol := try declarationLinkName(value.decl)
            defer symbol.free()
            ret try strings.concat("@", symbol)
        case dclr.DeclKind.EnumVariant:
            ret try enumVariantValue(value.decl)
        else:
            throw "LLVM value lowering currently supports variables, arguments, and functions"
        ..
    case nt.Expr.MemberAccess:
        memberNode := nt.loadExpressionNode(value.member)
        match addrof memberNode as memberValue:
        case nt.Expr.Named:
            if memberValue.decl == none:
                throw "member expression has no checked declaration in LLVM lowering"
            ..
            match memberValue.decl.kind as declarationKind:
            case dclr.DeclKind.Function:
                symbol := try declarationLinkName(memberValue.decl)
                defer symbol.free()
                ret try strings.concat("@", symbol)
            case dclr.DeclKind.EnumVariant:
                ret try enumVariantValue(memberValue.decl)
            case dclr.DeclKind.Variable:
                if declarationKind.isGlobal || (try isModuleVariable(memberValue.decl)):
                    symbol := try symbolName(memberValue.decl)
                    defer symbol.free()
                    resultType := try typeName(value.type)
                    defer resultType.free()
                    id := try strconv.formatUint(state.nextValue)
                    defer id.free()
                    state.nextValue = state.nextValue + 1
                    try state.output.appendBorrowed("  %v")
                    try state.output.appendCopy(id)
                    try state.output.appendBorrowed(" = load ")
                    try state.output.appendCopy(resultType)
                    try state.output.appendBorrowed(", ptr @")
                    try state.output.appendCopy(symbol)
                    try state.output.appendBorrowed("\n")
                    ret try strings.concat("%v", id)
                ..
            else:
                memberValue = memberValue
            ..
        else:
            throw "member access requires a resolved name"
        ..
        pointer := try emitLValuePointer(state, expression)
        defer pointer.free()
        resultType := try typeName(value.type)
        defer resultType.free()
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = load ")
        try state.output.appendCopy(resultType)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", id)
    case nt.Expr.Subscript:
        pointer := try emitLValuePointer(state, expression)
        defer pointer.free()
        subscriptResultType := try loweredTypeName(state, value.type)
        defer subscriptResultType.free()
        subscriptId := try strconv.formatUint(state.nextValue)
        defer subscriptId.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(subscriptId)
        try state.output.appendBorrowed(" = load ")
        try state.output.appendCopy(subscriptResultType)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", subscriptId)
    case nt.Expr.VarDef:
        if value.decl == none:
            throw "local variable has no linked declaration"
        ..
        localType := try loweredTypeName(state, value.type)
        defer localType.free()
        localId := try strconv.formatUint(value.decl.id)
        defer localId.free()
        try state.output.appendBorrowed("  store ")
        try state.output.appendCopy(localType)
        try state.output.appendBorrowed(" zeroinitializer, ptr %slot")
        try state.output.appendCopy(localId)
        try state.output.appendBorrowed("\n")
        ret try strings.copy("")
    case nt.Expr.VarDefAssign:
        if value.decl == none:
            throw "initialized local variable has no linked declaration"
        ..
        assigned := try emitExpr(state, value.assignment)
        defer assigned.free()
        localType := value.type
        if localType == none:
            match value.decl.kind as declarationKind:
            case dclr.DeclKind.Variable:
                localType = declarationKind.type
            else:
                localType = value.decl.declType
            ..
        ..
        if localType == none:
            assignedNode := nt.loadExpressionNode(value.assignment)
            match addrof assignedNode as arrayInitializer:
            case nt.Expr.Array:
                sliceNode := nt.Type.Slice(ofType=arrayInitializer.type).proto[nt.Node]()
                localType = try sliceNode.implBorrow[nt.Type]()
                value.type = localType
                value.decl.declType = localType
                match value.decl.kind as declarationKind:
                case dclr.DeclKind.Variable:
                    declarationKind.type = localType
                else:
                    value.decl = value.decl
                ..
            else:
                localType = none
            ..
        ..
        if localType != none:
            assignedType := try expressionType(value.assignment)
            if try isThrowingVoidType(assignedType):
                aggregateType := try typeName(assignedType)
                defer aggregateType.free()
                errorId := try strconv.formatUint(state.nextValue)
                defer errorId.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(errorId)
                try state.output.appendBorrowed(" = extractvalue ")
                try state.output.appendCopy(aggregateType)
                try state.output.appendBorrowed(" ")
                try state.output.appendCopy(assigned)
                try state.output.appendBorrowed(", 0\n")
                assigned.free()
                assigned = try strings.concat("%v", errorId)
                assignedType = localType
            ..
            converted str, conversionError error = coerceIntegerValue(state, assigned, assignedType, localType)
            if conversionError.nok():
                assigned.free()
                throw conversionError
            ..
            assigned.free()
            assigned = converted
        ..
        resultType str
        if localType == none:
            assignedNode := nt.loadExpressionNode(value.assignment)
            match addrof assignedNode as initializer:
            case nt.Expr.Array:
                resultType = try strings.copy("%type.slice")
            else:
                throw "initialized local has no checked storage type"
            ..
        else:
            resultType = try loweredTypeName(state, localType)
        ..
        defer resultType.free()
        id := try strconv.formatUint(value.decl.id)
        defer id.free()
        try state.output.appendBorrowed("  store ")
        try state.output.appendCopy(resultType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(assigned)
        try state.output.appendBorrowed(", ptr %slot")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed("\n")
        ret try strings.copy("")
    case nt.Expr.VarDefAssignDestructure:
        if value.valueDecl == none || value.errorDecl == none:
            throw "throwing-call destructure has unresolved local declarations"
        ..
        callType := try expressionType(value.call)
        if not isThrowingType(callType):
            throw "throwing-call destructure does not contain a throwing result"
        ..
        aggregate := try emitExpr(state, value.call)
        defer aggregate.free()
        innerType := try throwingValueType(callType)
        loweredInnerType := try typeName(innerType)
        defer loweredInnerType.free()
        errorSlot := try strconv.formatUint(value.errorDecl.id)
        defer errorSlot.free()
        valueSlot := try strconv.formatUint(value.valueDecl.id)
        defer valueSlot.free()
        loweredErrorType := try typeName(value.errorDecl.declType)
        defer loweredErrorType.free()
        errorValueId := try strconv.formatUint(state.nextValue)
        defer errorValueId.free()
        state.nextValue = state.nextValue + 1
        errorCodeId := try strconv.formatUint(state.nextValue)
        defer errorCodeId.free()
        state.nextValue = state.nextValue + 1
        failedId := try strconv.formatUint(state.nextValue)
        defer failedId.free()
        state.nextValue = state.nextValue + 1
        payloadId := try strconv.formatUint(state.nextValue)
        defer payloadId.free()
        state.nextValue = state.nextValue + 1
        blockId := try strconv.formatUint(state.nextBlock)
        defer blockId.free()
        state.nextBlock = state.nextBlock + 1
        failedLabel := try strings.concat("destructure_failed_", blockId)
        defer failedLabel.free()
        successLabel := try strings.concat("destructure_success_", blockId)
        defer successLabel.free()
        endLabel := try strings.concat("destructure_end_", blockId)
        defer endLabel.free()
        throwingTypeName := try typeName(callType)
        defer throwingTypeName.free()
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(errorValueId)
        try state.output.appendBorrowed(" = extractvalue ")
        try state.output.appendCopy(throwingTypeName)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(aggregate)
        try state.output.appendBorrowed(", 0\n  %v")
        try state.output.appendCopy(errorCodeId)
        try state.output.appendBorrowed(" = extractvalue %type.error %v")
        try state.output.appendCopy(errorValueId)
        try state.output.appendBorrowed(", 1\n  %v")
        try state.output.appendCopy(failedId)
        try state.output.appendBorrowed(" = icmp ne i32 %v")
        try state.output.appendCopy(errorCodeId)
        try state.output.appendBorrowed(", 0\n  br i1 %v")
        try state.output.appendCopy(failedId)
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(failedLabel)
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(successLabel)
        try state.output.appendBorrowed("\n")
        try state.output.appendCopy(successLabel)
        try state.output.appendBorrowed(":\n  %v")
        try state.output.appendCopy(payloadId)
        try state.output.appendBorrowed(" = extractvalue ")
        try state.output.appendCopy(throwingTypeName)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(aggregate)
        try state.output.appendBorrowed(", 1\n  store ")
        try state.output.appendCopy(loweredInnerType)
        try state.output.appendBorrowed(" %v")
        try state.output.appendCopy(payloadId)
        try state.output.appendBorrowed(", ptr %slot")
        try state.output.appendCopy(valueSlot)
        try state.output.appendBorrowed("\n  br label %")
        try state.output.appendCopy(endLabel)
        try state.output.appendBorrowed("\n")
        try state.output.appendCopy(failedLabel)
        try state.output.appendBorrowed(":\n  store ")
        try state.output.appendCopy(loweredErrorType)
        try state.output.appendBorrowed(" %v")
        try state.output.appendCopy(errorValueId)
        try state.output.appendBorrowed(", ptr %slot")
        try state.output.appendCopy(errorSlot)
        try state.output.appendBorrowed("\n  br label %")
        try state.output.appendCopy(endLabel)
        try state.output.appendBorrowed("\n")
        try state.output.appendCopy(endLabel)
        try state.output.appendBorrowed(":\n")
        try setCurrentBlock(state, endLabel)
        ret try strings.copy("")
    case nt.Expr.Assign:
        assigned := try emitExpr(state, value.expr)
        defer assigned.free()
        targetType := try expressionType(value.assignee)
        sourceType := try expressionType(value.expr)
        assignedValue := try coerceIntegerValue(state, assigned, sourceType, targetType)
        defer assignedValue.free()
        resultType := try typeName(targetType)
        defer resultType.free()
        pointer := try emitLValuePointer(state, value.assignee)
        defer pointer.free()
        try state.output.appendBorrowed("  store ")
        try state.output.appendCopy(resultType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(assignedValue)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed("\n")
        # Keep the deferred local alive through emission and return an
        # independent owned string. Moving assignedValue here would still run
        # its deferred free when this scope exits.
        ret try strings.copy(assignedValue)
    case nt.Expr.DirectCall:
        ret try emitResolvedCall(state, value.callKind, value.decl, none, value.type, value.args, value.typeArgs)
    case nt.Expr.TemplatedDirectCall:
        ret try emitResolvedCall(state, value.callKind, value.decl, none, value.type, value.args, value.typeArgs)
    case nt.Expr.IndirectCall:
        ret try emitResolvedCall(state, value.callKind, value.target, value.owner, value.type, value.args, value.typeArgs)
    case nt.Expr.TemplatedIndirectCall:
        ret try emitResolvedCall(state, value.callKind, value.target, value.owner, value.type, value.args, value.typeArgs)
    case nt.Expr.GenericApply:
        ownerNode := nt.loadExpressionNode(value.owner)
        match addrof ownerNode as ownerValue:
        case nt.Expr.Named:
            if ownerValue.decl == none:
                throw "generic application has no linked declaration"
            ..
            specialization := try loweredSpecializationSymbol(state, ownerValue.decl, value.typeArgs)
            defer specialization.free()
            ret try strings.concat("@", specialization)
        else:
            throw "unsupported generic function value"
        ..
    case nt.Expr.InlineLLVM:
        ret try emitInlineLLVM(state, value.operation, value.type, value.args)
    case nt.Expr.Embed:
        content := try fs.readFile(value.path)
        defer content.free()
        arrayLength := try strconv.formatUint(content.countBytes() + 1)
        defer arrayLength.free()
        byteCount := try strconv.formatUint(content.countBytes())
        defer byteCount.free()
        storageId := try strconv.formatUint(state.nextValue)
        defer storageId.free()
        state.nextValue = state.nextValue + 1
        pointerId := try strconv.formatUint(state.nextValue)
        defer pointerId.free()
        state.nextValue = state.nextValue + 1
        firstId := try strconv.formatUint(state.nextValue)
        defer firstId.free()
        state.nextValue = state.nextValue + 1
        secondId := try strconv.formatUint(state.nextValue)
        defer secondId.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(storageId)
        try state.output.appendBorrowed(" = alloca [")
        try state.output.appendCopy(arrayLength)
        try state.output.appendBorrowed(" x i8], align 1\n  store [")
        try state.output.appendCopy(arrayLength)
        try state.output.appendBorrowed(" x i8] c\"")
        try appendLLVMBytes(state.output, content)
        try state.output.appendBorrowed("\\00\", ptr %v")
        try state.output.appendCopy(storageId)
        try state.output.appendBorrowed("\n  %v")
        try state.output.appendCopy(pointerId)
        try state.output.appendBorrowed(" = getelementptr inbounds [")
        try state.output.appendCopy(arrayLength)
        try state.output.appendBorrowed(" x i8], ptr %v")
        try state.output.appendCopy(storageId)
        try state.output.appendBorrowed(", i64 0, i64 0\n  %v")
        try state.output.appendCopy(firstId)
        try state.output.appendBorrowed(" = insertvalue %type.str zeroinitializer, ptr %v")
        try state.output.appendCopy(pointerId)
        try state.output.appendBorrowed(", 0\n  %v")
        try state.output.appendCopy(secondId)
        try state.output.appendBorrowed(" = insertvalue %type.str %v")
        try state.output.appendCopy(firstId)
        try state.output.appendBorrowed(", i64 ")
        try state.output.appendCopy(byteCount)
        try state.output.appendBorrowed(", 1\n")
        ret try strings.concat("%v", secondId)
    case nt.Expr.Sizeof:
        lowered := try loweredTypeName(state, value.operand)
        defer lowered.free()
        prefix := try strings.concat("ptrtoint (ptr getelementptr (", lowered)
        defer prefix.free()
        middle := try strings.concat(prefix, ", ptr null, i64 1) to i64)")
        ret move middle
    case nt.Expr.Move:
        ret try emitExpr(state, value.operand)
    case nt.Expr.Try:
        lowered := try emitTry(state, value.call)
        ret move lowered
    case nt.Expr.Binary:
        ret try emitBinary(state, value.type, value.op, value.left, value.right, value.protoEquality, value.stringEquality, value.floatingPoint, value.unsignedOperation)
    case nt.Expr.Unary:
        if value.op == tokens.KwType.AMPERSAND || value.op == tokens.KwType.ADDROF:
            ret try emitLValuePointer(state, value.operand)
        elif value.op == tokens.KwType.ASTERIX:
            pointer := try emitExpr(state, value.operand)
            defer pointer.free()
            resultType := try typeName(value.type)
            defer resultType.free()
            id := try strconv.formatUint(state.nextValue)
            defer id.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(id)
            try state.output.appendBorrowed(" = load ")
            try state.output.appendCopy(resultType)
            try state.output.appendBorrowed(", ptr ")
            try state.output.appendCopy(pointer)
            try state.output.appendBorrowed("\n")
            ret try strings.concat("%v", id)
        elif value.op == tokens.KwType.MINUS || value.op == tokens.KwType.NOT || value.op == tokens.KwType.TILDE:
            operand := try emitExpr(state, value.operand)
            defer operand.free()
            resultType := try typeName(value.type)
            defer resultType.free()
            id := try strconv.formatUint(state.nextValue)
            defer id.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(id)
            if value.op == tokens.KwType.MINUS:
                if value.floatingPoint:
                    try state.output.appendBorrowed(" = fneg ")
                    try state.output.appendCopy(resultType)
                    try state.output.appendBorrowed(" ")
                    try state.output.appendCopy(operand)
                else:
                    try state.output.appendBorrowed(" = sub ")
                    try state.output.appendCopy(resultType)
                    try state.output.appendBorrowed(" 0, ")
                    try state.output.appendCopy(operand)
                ..
            elif value.op == tokens.KwType.NOT:
                try state.output.appendBorrowed(" = xor i1 ")
                try state.output.appendCopy(operand)
                try state.output.appendBorrowed(", 1")
            else:
                try state.output.appendBorrowed(" = xor ")
                try state.output.appendCopy(resultType)
                try state.output.appendBorrowed(" ")
                try state.output.appendCopy(operand)
                try state.output.appendBorrowed(", -1")
            ..
            try state.output.appendBorrowed("\n")
            prefix := try strings.concat("%v", id)
            ret move prefix
        ..
        throw "unsupported unary expression in LLVM lowering"
    else:
        throw "unsupported expression in LLVM lowering"
    ..
..

inlineOperand(state LoweringState*, args nt.NodeArray[nt.Expr*], index u64) !$str:
    if index >= args.count():
        throw "inline LLVM operation has too few operands"
    ..
    operand := try args.get(index)
    ret try emitExpr(state, operand)
..

inlineOperandType(args nt.NodeArray[nt.Expr*], index u64) !$str:
    if index >= args.count():
        throw "inline LLVM operation has too few operands"
    ..
    operand := try args.get(index)
    ret try typeName(try expressionType(operand))
..

inlineStringArgument(args nt.NodeArray[nt.Expr*], index u64) !$str:
    if index >= args.count():
        throw "inline LLVM operation has too few operands"
    ..
    operand := nt.loadExpressionNode(try args.get(index))
    match addrof operand as value:
    case nt.Expr.Literal:
        match value.literal as literal:
        case nt.Literal.String:
            ret try strings.copy(literal.value)
        case nt.Literal.Number:
            ret try strings.copy(literal.value)
        else:
            throw "inline LLVM token operand must be a string or number literal"
        ..
    else:
        throw "inline LLVM token operand must be a compile-time literal"
    ..
..

emitInlineLLVM(state LoweringState*, operation str, resultType nt.Type*, args nt.NodeArray[nt.Expr*]) !$str:
    result := try typeName(resultType)
    defer result.free()
    if strings.compare(operation, "offset"):
        if args.count() != 2:
            throw "@llvm offset expects a pointer and byte offset"
        ..
        pointer := try inlineOperand(state, args, 0)
        defer pointer.free()
        offset := try inlineOperand(state, args, 1)
        defer offset.free()
        offsetType := try inlineOperandType(args, 1)
        defer offsetType.free()
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = getelementptr i8, ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(offsetType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(offset)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", id)
    elif strings.compare(operation, "ptrtoint") || strings.compare(operation, "inttoptr") || strings.compare(operation, "sext") || strings.compare(operation, "zext") || strings.compare(operation, "trunc") || strings.compare(operation, "bitcast") || strings.compare(operation, "sitofp") || strings.compare(operation, "uitofp") || strings.compare(operation, "fptosi") || strings.compare(operation, "fptoui") || strings.compare(operation, "reinterpret"):
        if args.count() != 1:
            throw "inline LLVM cast operation expects one operand"
        ..
        source := try inlineOperand(state, args, 0)
        defer source.free()
        sourceType := try inlineOperandType(args, 0)
        defer sourceType.free()
        if strings.compare(operation, "reinterpret") && strings.compare(sourceType, result):
            ret try strings.copy(source)
        ..
        opcode := operation
        if strings.compare(operation, "reinterpret"):
            if strings.compare(sourceType, "ptr"):
                opcode = "ptrtoint"
            elif strings.compare(result, "ptr"):
                opcode = "inttoptr"
            else:
                opcode = "bitcast"
            ..
        ..
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = ")
        try state.output.appendCopy(opcode)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(sourceType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(source)
        try state.output.appendBorrowed(" to ")
        try state.output.appendCopy(result)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", id)
    elif strings.compare(operation, "load_volatile"):
        if args.count() != 2:
            throw "@llvm load_volatile expects pointer and alignment"
        ..
        pointer := try inlineOperand(state, args, 0)
        defer pointer.free()
        alignment := try inlineStringArgument(args, 1)
        defer alignment.free()
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = load volatile ")
        try state.output.appendCopy(result)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(", align ")
        try state.output.appendCopy(alignment)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", id)
    elif strings.compare(operation, "store_volatile"):
        if args.count() != 3:
            throw "@llvm store_volatile expects pointer, value, and alignment"
        ..
        pointer := try inlineOperand(state, args, 0)
        defer pointer.free()
        value := try inlineOperand(state, args, 1)
        defer value.free()
        alignment := try inlineStringArgument(args, 2)
        defer alignment.free()
        valueType := try inlineOperandType(args, 1)
        defer valueType.free()
        try state.output.appendBorrowed("  store volatile ")
        try state.output.appendCopy(valueType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(value)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(", align ")
        try state.output.appendCopy(alignment)
        try state.output.appendBorrowed("\n")
        ret try strings.copy("")
    elif strings.compare(operation, "atomic_load"):
        if args.count() != 3:
            throw "@llvm atomic_load expects pointer, ordering, and alignment"
        ..
        pointer := try inlineOperand(state, args, 0)
        defer pointer.free()
        ordering := try inlineStringArgument(args, 1)
        defer ordering.free()
        alignment := try inlineStringArgument(args, 2)
        defer alignment.free()
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = load atomic ")
        try state.output.appendCopy(result)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(ordering)
        try state.output.appendBorrowed(", align ")
        try state.output.appendCopy(alignment)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", id)
    elif strings.compare(operation, "atomic_store"):
        if args.count() != 4:
            throw "@llvm atomic_store expects pointer, value, ordering, and alignment"
        ..
        pointer := try inlineOperand(state, args, 0)
        defer pointer.free()
        value := try inlineOperand(state, args, 1)
        defer value.free()
        valueType := try inlineOperandType(args, 1)
        defer valueType.free()
        ordering := try inlineStringArgument(args, 2)
        defer ordering.free()
        alignment := try inlineStringArgument(args, 3)
        defer alignment.free()
        try state.output.appendBorrowed("  store atomic ")
        try state.output.appendCopy(valueType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(value)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(ordering)
        try state.output.appendBorrowed(", align ")
        try state.output.appendCopy(alignment)
        try state.output.appendBorrowed("\n")
        ret try strings.copy("")
    elif strings.compare(operation, "atomic_rmw"):
        if args.count() != 5:
            throw "@llvm atomic_rmw expects pointer, value, operation, ordering, and alignment"
        ..
        pointer := try inlineOperand(state, args, 0)
        defer pointer.free()
        value := try inlineOperand(state, args, 1)
        defer value.free()
        valueType := try inlineOperandType(args, 1)
        defer valueType.free()
        atomicOperation := try inlineStringArgument(args, 2)
        defer atomicOperation.free()
        ordering := try inlineStringArgument(args, 3)
        defer ordering.free()
        alignment := try inlineStringArgument(args, 4)
        defer alignment.free()
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = atomicrmw ")
        try state.output.appendCopy(atomicOperation)
        try state.output.appendBorrowed(" ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(valueType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(value)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(ordering)
        try state.output.appendBorrowed(", align ")
        try state.output.appendCopy(alignment)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", id)
    elif strings.compare(operation, "cmpxchg_old"):
        if args.count() != 6:
            throw "@llvm cmpxchg_old expects pointer, expected, desired, success order, failure order, and alignment"
        ..
        pointer := try inlineOperand(state, args, 0)
        defer pointer.free()
        expected := try inlineOperand(state, args, 1)
        defer expected.free()
        desired := try inlineOperand(state, args, 2)
        defer desired.free()
        valueType := try inlineOperandType(args, 1)
        defer valueType.free()
        successOrdering := try inlineStringArgument(args, 3)
        defer successOrdering.free()
        failureOrdering := try inlineStringArgument(args, 4)
        defer failureOrdering.free()
        alignment := try inlineStringArgument(args, 5)
        defer alignment.free()
        pairId := try strconv.formatUint(state.nextValue)
        defer pairId.free()
        state.nextValue = state.nextValue + 1
        oldId := try strconv.formatUint(state.nextValue)
        defer oldId.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(pairId)
        try state.output.appendBorrowed(" = cmpxchg ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(valueType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(expected)
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(valueType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(desired)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(successOrdering)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(failureOrdering)
        try state.output.appendBorrowed(", align ")
        try state.output.appendCopy(alignment)
        try state.output.appendBorrowed("\n  %v")
        try state.output.appendCopy(oldId)
        try state.output.appendBorrowed(" = extractvalue { ")
        try state.output.appendCopy(valueType)
        try state.output.appendBorrowed(", i1 } %v")
        try state.output.appendCopy(pairId)
        try state.output.appendBorrowed(", 0\n")
        ret try strings.concat("%v", oldId)
    elif strings.compare(operation, "asm_sideeffect") || strings.compare(operation, "sideeffect"):
        if strings.compare(operation, "asm_sideeffect"):
            if args.count() != 1:
                throw "@llvm asm_sideeffect expects one assembly string"
            ..
            assembly := try inlineStringArgument(args, 0)
            defer assembly.free()
            try state.output.appendBorrowed("  call void asm sideeffect \"")
            try state.output.appendCopy(assembly)
            try state.output.appendBorrowed("\", \"~{memory}\"()\n")
        else:
            if args.count() != 0:
                throw "@llvm sideeffect expects no operands"
            ..
            try state.output.appendBorrowed("  call void asm sideeffect \"\", \"~{memory}\"()\n")
        ..
        ret try strings.copy("")
    elif strings.compare(operation, "expect"):
        if args.count() != 2:
            throw "@llvm expect expects a value and expected value"
        ..
        ret try inlineOperand(state, args, 0)
    elif strings.compare(operation, "fence"):
        if args.count() != 1:
            throw "@llvm fence expects one ordering"
        ..
        ordering := try inlineStringArgument(args, 0)
        defer ordering.free()
        try state.output.appendBorrowed("  fence ")
        try state.output.appendCopy(ordering)
        try state.output.appendBorrowed("\n")
        ret try strings.copy("")
    elif strings.compare(operation, "assume"):
        if args.count() != 1:
            throw "@llvm assume expects one condition"
        ..
        condition := try inlineOperand(state, args, 0)
        defer condition.free()
        try state.output.appendBorrowed("  call void @llvm.assume(i1 ")
        try state.output.appendCopy(condition)
        try state.output.appendBorrowed(")\n")
        ret try strings.copy("")
    elif strings.compare(operation, "trap"):
        if args.count() != 0:
            throw "@llvm trap expects no operands"
        ..
        try state.output.appendBorrowed("  call void @llvm.trap()\n")
        ret try strings.copy("")
    elif strings.compare(operation, "bswap") || strings.compare(operation, "bitreverse") || strings.compare(operation, "ctpop") || strings.compare(operation, "ctlz") || strings.compare(operation, "cttz"):
        expectedCount u64 = 1
        if args.count() != expectedCount:
            throw "LLVM bit intrinsic received an invalid operand count"
        ..
        operand := try inlineOperand(state, args, 0)
        defer operand.free()
        operandType := try inlineOperandType(args, 0)
        defer operandType.free()
        intrinsicName := try strings.concat("@llvm.", operation)
        defer intrinsicName.free()
        intrinsicType := try strings.concat(intrinsicName, ".")
        defer intrinsicType.free()
        typedName := try strings.concat(intrinsicType, result)
        defer typedName.free()
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = call ")
        try state.output.appendCopy(result)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(typedName)
        try state.output.appendBorrowed("(")
        try state.output.appendCopy(operandType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(operand)
        if strings.compare(operation, "ctlz") || strings.compare(operation, "cttz"):
            # false requests the defined result for a zero input: the full width.
            try state.output.appendBorrowed(", i1 false")
        ..
        try state.output.appendBorrowed(")\n")
        ret try strings.concat("%v", id)
    else:
        throw "unsupported inline LLVM operation"
    ..
..

structDeclaration(type nt.Type*) !dclr.Decl*:
    if type == none:
        throw "member access owner has no checked type"
    ..
    match type as value:
    case nt.Type.Owned:
        ret try structDeclaration(value.ofType)
    case nt.Type.Pointer:
        ret try structDeclaration(value.toType)
    case nt.Type.Templated:
        ret try structDeclaration(value.owner)
    case nt.Type.Named:
        if value.decl == none:
            throw "unresolved named type in LLVM field access"
        ..
        match value.decl.kind as declarationKind:
        case dclr.DeclKind.Struct:
            ret value.decl
        case dclr.DeclKind.Proto:
            ret value.decl
        case dclr.DeclKind.Union:
            ret value.decl
        case dclr.DeclKind.UnionVariant:
            ret value.decl
        case dclr.DeclKind.Alias:
            ret try structDeclaration(declarationKind.target)
        else:
            throw "member access owner is not a structure"
        ..
    else:
        throw "member access owner is not a structure"
    ..
..

alignOffset(value u64, alignment u64) u64:
    if alignment <= 1:
        ret value
    ..
    remainder := value % alignment
    if remainder == 0:
        ret value
    ..
    ret value + alignment - remainder
..

layoutFields(fields dclr.DeclArray, depth u64) !TypeLayout:
    offset u64 = 0
    maximumAlignment u64 = 1
    for i := 0 to fields.count():
        field := try fields.get(i)
        match field.kind as kind:
        case dclr.DeclKind.Field:
            fieldLayout := try layoutOfType(kind.type, depth + 1)
            if fieldLayout.alignment > maximumAlignment:
                maximumAlignment = fieldLayout.alignment
            ..
            offset = alignOffset(offset, fieldLayout.alignment)
            offset = offset + fieldLayout.size
        else:
            throw "non-field declaration in aggregate layout"
        ..
    ..
    ret TypeLayout(size=alignOffset(offset, maximumAlignment), alignment=maximumAlignment)
..

specializedStructHeader(type nt.Type*) !nt.Header*:
    match type as concreteType:
    case nt.Type.Templated:
        templateDecl := try structDeclaration(concreteType.owner)
        templateModule := try gl.files.get(templateDecl.module.path)
        targetSymbol := try specializationSymbol(templateDecl, concreteType.args)
        defer targetSymbol.free()
        for i := 0 to templateModule.specializations.count():
            candidate := try templateModule.specializations.get(i)
            if candidate.isFunction || candidate.template != templateDecl || candidate.concreteHeader == none:
                continue
            ..
            candidateSymbol := try specializationSymbol(candidate.template, candidate.typeArgs)
            defer candidateSymbol.free()
            if strings.compare(candidateSymbol, targetSymbol):
                ret candidate.concreteHeader
            ..
        ..
        throw "checked generic structure specialization is missing"
    else:
        throw "type is not a specialized structure"
    ..
..

layoutSpecializedHeader(header nt.Header*, depth u64) !TypeLayout:
    offset u64 = 0
    maximumAlignment u64 = 1
    for i := 0 to header.fields.count():
        expression := nt.loadExpressionNode(try header.fields.get(i))
        match addrof expression as field:
        case nt.Expr.VarDef:
            fieldLayout := try layoutOfType(field.type, depth + 1)
            if fieldLayout.alignment > maximumAlignment:
                maximumAlignment = fieldLayout.alignment
            ..
            offset = alignOffset(offset, fieldLayout.alignment)
            offset = offset + fieldLayout.size
        else:
            throw "specialized structure contains a non-field"
        ..
    ..
    ret TypeLayout(size=alignOffset(offset, maximumAlignment), alignment=maximumAlignment)
..

unionPayloadLayout(declaration dclr.Decl*, depth u64) !TypeLayout:
    match declaration.kind as unionKind:
    case dclr.DeclKind.Union:
        payloadSize u64 = 0
        payloadAlignment u64 = 1
        for i := 0 to unionKind.variants.count():
            variant := try unionKind.variants.get(i)
            match variant.kind as variantKind:
            case dclr.DeclKind.UnionVariant:
                variantLayout := try layoutFields(variantKind.fields, depth + 1)
                if variantLayout.size > payloadSize:
                    payloadSize = variantLayout.size
                ..
                if variantLayout.alignment > payloadAlignment:
                    payloadAlignment = variantLayout.alignment
                ..
            else:
                throw "union contains a non-variant declaration"
            ..
        ..
        ret TypeLayout(size=payloadSize, alignment=payloadAlignment)
    else:
        throw "aggregate is not a union"
    ..
..

unionVariantInfo(variantDecl dclr.Decl*) !UnionVariantInfo:
    if variantDecl == none || variantDecl.unionOwner == none:
        throw "union variant has no checked owner declaration"
    ..
    ret UnionVariantInfo(unionDecl=variantDecl.unionOwner, tag=variantDecl.unionTag)
..

layoutOfType(type nt.Type*, depth u64) !TypeLayout:
    if type == none || depth > 64:
        throw "unsupported or excessively nested type layout"
    ..
    match type as value:
    case nt.Type.Pointer:
        ret TypeLayout(size=8, alignment=8)
    case nt.Type.Function:
        ret TypeLayout(size=8, alignment=8)
    case nt.Type.Slice:
        ret TypeLayout(size=16, alignment=8)
    case nt.Type.Owned:
        ret try layoutOfType(value.ofType, depth + 1)
    case nt.Type.Throwing:
        inner := try layoutOfType(value.ofType, depth + 1)
        alignment u64 = 8
        if inner.alignment > alignment:
            alignment = inner.alignment
        ..
        offset := alignOffset(16, inner.alignment) + inner.size
        ret TypeLayout(size=alignOffset(offset, alignment), alignment=alignment)
    case nt.Type.CompilerKnown:
        throw "unresolved compiler-known type reached LLVM layout"
    case nt.Type.Named:
        if value.decl == none:
            simpleType := try typeName(type)
            defer simpleType.free()
            if strings.compare(simpleType, "ptr"):
                ret TypeLayout(size=8, alignment=8)
            elif strings.compare(simpleType, "i1") || strings.compare(simpleType, "i8"):
                ret TypeLayout(size=1, alignment=1)
            elif strings.compare(simpleType, "i16") || strings.compare(simpleType, "half"):
                ret TypeLayout(size=2, alignment=2)
            elif strings.compare(simpleType, "i32") || strings.compare(simpleType, "float"):
                ret TypeLayout(size=4, alignment=4)
            elif strings.compare(simpleType, "i64") || strings.compare(simpleType, "double"):
                ret TypeLayout(size=8, alignment=8)
            elif strings.compare(simpleType, "i128") || strings.compare(simpleType, "fp128"):
                ret TypeLayout(size=16, alignment=16)
            elif strings.compare(simpleType, "%type.str"):
                ret TypeLayout(size=32, alignment=8)
            elif strings.compare(simpleType, "%type.error"):
                ret TypeLayout(size=16, alignment=8)
            elif strings.compare(simpleType, "%type.slice"):
                ret TypeLayout(size=16, alignment=8)
            ..
            throw "unsupported unresolved named type layout"
        ..
        match value.decl.kind as declarationKind:
        case dclr.DeclKind.Alias:
            ret try layoutOfType(declarationKind.target, depth + 1)
        case dclr.DeclKind.Enum:
            ret try layoutOfType(declarationKind.backing, depth + 1)
        case dclr.DeclKind.Struct:
            ret try layoutFields(declarationKind.fields, depth + 1)
        case dclr.DeclKind.UnionVariant:
            ret try layoutFields(declarationKind.fields, depth + 1)
        case dclr.DeclKind.Union:
            payload := try unionPayloadLayout(value.decl, depth + 1)
            alignment u64 = payload.alignment
            if alignment < 4:
                alignment = 4
            ..
            offset := alignOffset(4, payload.alignment) + payload.size
            ret TypeLayout(size=alignOffset(offset, alignment), alignment=alignment)
        else:
            throw "declaration has no aggregate value layout"
        ..
    case nt.Type.Templated:
        header := try specializedStructHeader(type)
        ret try layoutSpecializedHeader(header, depth + 1)
    else:
        throw "unsupported type in aggregate layout"
    ..
..

alignmentType(alignment u64) str:
    if alignment >= 16: ret "i128" ..
    if alignment >= 8: ret "i64" ..
    if alignment >= 4: ret "i32" ..
    if alignment >= 2: ret "i16" ..
    ret "i8"
..

emitUnionLayout(out builder.Builder*, declaration dclr.Decl*) !void:
    payload := try unionPayloadLayout(declaration, 0)
    alignment := alignmentType(payload.alignment)
    payloadSize := try strconv.formatUint(payload.size)
    defer payloadSize.free()
    symbol := try typeIdentity(declaration)
    defer symbol.free()
    try out.appendBorrowed("%")
    try out.appendCopy(symbol)
    try out.appendBorrowed(" = type { i32, [0 x ")
    try out.appendCopy(alignment)
    try out.appendBorrowed("], [")
    try out.appendCopy(payloadSize)
    try out.appendBorrowed(" x i8] }\n")
..

fieldIndex(ownerType nt.Type*, field dclr.Decl*) !$u64:
    if ownerType == none || field == none:
        throw "field index requires checked owner and field declarations"
    ..
    _ := try structDeclaration(ownerType)
    ret field.fieldIndex
..

isModuleVariable(declaration dclr.Decl*) !bool:
    if declaration == none:
        ret false
    ..
    ret declaration.isModuleVariable
..

emitLValuePointer(state LoweringState*, expression nt.Expr*) !$str:
    node := nt.loadExpressionNode(expression)
    match addrof node as value:
    case nt.Expr.Named:
        if value.decl == none:
            throw "unresolved assignment target"
        ..
        if value.decl.isImplicitContext:
            if state.hasContext:
                ret try strings.copy("%ctx.in")
            ..
            if state.hasLocalContext:
                id := try strconv.formatUint(state.localContextId)
                defer id.free()
                ret try strings.concat("%slot", id)
            ..
            throw "implicit context binding has no storage in this function"
        ..
        if sameDeclarationIdentity(state.matchBindingDecl, value.decl):
            bindingId := try strconv.formatUint(state.matchBindingPointerId)
            defer bindingId.free()
            if state.matchBindingPointerKind == 1:
                ret try strings.concat("%v", bindingId)
            ..
            ret try strings.concat("%slot", bindingId)
        ..
        match value.decl.kind as declarationKind:
        case dclr.DeclKind.Variable:
            if declarationKind.isGlobal || (try isModuleVariable(value.decl)):
                symbol := try symbolName(value.decl)
                defer symbol.free()
                ret try strings.concat("@", symbol)
            ..
            id := try strconv.formatUint(value.decl.id)
            defer id.free()
            ret try strings.concat("%slot", id)
        case dclr.DeclKind.Argument:
            id := try strconv.formatUint(value.decl.id)
            defer id.free()
            ret try strings.concat("%slot", id)
        else:
            throw "name is not an assignable variable"
        ..
    case nt.Expr.Unary:
        if value.op != tokens.KwType.ASTERIX:
            throw "unary expression is not a dereference target"
        ..
        ret try emitExpr(state, value.operand)
    case nt.Expr.MemberAccess:
        if value.member == none:
            throw "member access has no resolved member"
        ..
        memberNode := nt.loadExpressionNode(value.member)
        field dclr.Decl* = none
        match addrof memberNode as memberValue:
        case nt.Expr.Named:
            field = memberValue.decl
        else:
            throw "member access does not resolve to a named field"
        ..
        if field == none:
            throw "member access has no checked field declaration in LLVM lowering"
        ..
        match field.kind as fieldKind:
        case dclr.DeclKind.Variable:
            if fieldKind.isGlobal || (try isModuleVariable(field)):
                symbol := try symbolName(field)
                defer symbol.free()
                ret try strings.concat("@", symbol)
            ..
        else:
            field = field
        ..
        ownerType := try loweredConcreteType(state, try expressionType(value.owner))
        if ownerType == none:
            fieldName := try symbolName(field)
            message str, messageError error = strings.concat("cannot lower member access with unresolved owner type: ", fieldName)
            if messageError.nok():
                fieldName.free()
                throw messageError
            ..
            fieldName.free()
            throw move message
        ..
        ownerTypeName := try typeName(ownerType)
        ownerTypeName.free()
        match ownerType as debugOwnerType:
        case nt.Type.Pointer:
            targetName := try typeName(debugOwnerType.toType)
            targetName.free()
        else:
        ..
        if ownerType == none:
            throw "member access owner has no checked type"
        ..
        index := try fieldIndex(ownerType, field)
        concreteOwnerType := ownerType
        match ownerType as ownerKind:
        case nt.Type.Pointer:
            concreteOwnerType = ownerKind.toType
        else:
            concreteOwnerType = ownerType
        ..
        structLlvmType := try typeName(concreteOwnerType)
        defer structLlvmType.free()
        pointer str
        match ownerType as ownerTypeValue:
        case nt.Type.Pointer:
            pointer = try emitExpr(state, value.owner)
        else:
            if try isAssignableExpression(value.owner):
                pointer = try emitLValuePointer(state, value.owner)
            else:
                ownerValue := try emitExpr(state, value.owner)
                defer ownerValue.free()
                slotType := try typeName(ownerType)
                defer slotType.free()
                slot := try strconv.formatUint(state.nextValue)
                defer slot.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %tmp.slot")
                try state.output.appendCopy(slot)
                try state.output.appendBorrowed(" = alloca ")
                try state.output.appendCopy(slotType)
                try state.output.appendBorrowed("\n  store ")
                try state.output.appendCopy(slotType)
                try state.output.appendBorrowed(" ")
                try state.output.appendCopy(ownerValue)
                try state.output.appendBorrowed(", ptr %tmp.slot")
                try state.output.appendCopy(slot)
                try state.output.appendBorrowed("\n")
                pointer = try strings.concat("%tmp.slot", slot)
            ..
        ..
        defer pointer.free()
        indexText := try strconv.formatUint(index)
        defer indexText.free()
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = getelementptr ")
        try state.output.appendCopy(structLlvmType)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(", i32 0, i32 ")
        try state.output.appendCopy(indexText)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", id)
    case nt.Expr.Subscript:
        ownerNode := nt.loadExpressionNode(value.owner)
        match addrof ownerNode as ownerValue:
        case nt.Expr.Named:
        else:
        ..
        ownerType := try loweredConcreteType(state, try expressionType(value.owner))
        ownerTypeName := try typeName(ownerType)
        ownerTypeName.free()
        elementType nt.Type* = none
        pointer str
        match ownerType as ownerTypeValue:
        case nt.Type.Pointer:
            elementType = ownerTypeValue.toType
            pointer = try emitExpr(state, value.owner)
        case nt.Type.Slice:
            elementType = ownerTypeValue.ofType
            sliceValue := try emitExpr(state, value.owner)
            defer sliceValue.free()
            sliceId := try strconv.formatUint(state.nextValue)
            defer sliceId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(sliceId)
            try state.output.appendBorrowed(" = extractvalue %type.slice ")
            try state.output.appendCopy(sliceValue)
            try state.output.appendBorrowed(", 0\n")
            pointer = try strings.concat("%v", sliceId)
        case nt.Type.Named:
            subscriptTypeName := try typeName(ownerType)
            defer subscriptTypeName.free()
            if strings.compare(subscriptTypeName, "ptr"):
                elementType = try expressionType(expression)
                pointer = try emitExpr(state, value.owner)
            else:
                throw "subscript owner must be a pointer or slice"
            ..
        case nt.Type.CompilerKnown:
            throw "unresolved compiler-known subscript owner reached LLVM lowering"
        case nt.Type.Owned:
            match ownerTypeValue.ofType as ownedType:
            case nt.Type.Pointer:
                elementType = ownedType.toType
                pointer = try emitExpr(state, value.owner)
            case nt.Type.Slice:
                elementType = ownedType.ofType
                sliceValue := try emitExpr(state, value.owner)
                defer sliceValue.free()
                sliceId := try strconv.formatUint(state.nextValue)
                defer sliceId.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(sliceId)
                try state.output.appendBorrowed(" = extractvalue %type.slice ")
                try state.output.appendCopy(sliceValue)
                try state.output.appendBorrowed(", 0\n")
                pointer = try strings.concat("%v", sliceId)
            else:
                throw "subscript owner must be a pointer or slice"
            ..
        else:
            unexpectedType := try typeName(ownerType)
            defer unexpectedType.free()
            throw try strings.concat("subscript owner must be a pointer or slice, got ", unexpectedType)
        ..
        defer pointer.free()
        elementType = try loweredConcreteType(state, elementType)
        loweredElement := try loweredTypeName(state, elementType)
        defer loweredElement.free()
        index := try emitExpr(state, value.index)
        defer index.free()
        indexType := try loweredTypeName(state, try expressionType(value.index))
        defer indexType.free()
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = getelementptr ")
        try state.output.appendCopy(loweredElement)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(pointer)
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(indexType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(index)
        try state.output.appendBorrowed("\n")
        ret try strings.concat("%v", id)
    else:
        throw "expression is not assignable"
    ..
..

emitCall(state LoweringState*, returnType nt.Type*, declaration dclr.Decl*, args nt.NodeArray[nt.Expr*]) !$str:
    if declaration == none:
        throw "direct call has no resolved function declaration"
    ..
    symbol := try declarationLinkName(declaration)
    defer symbol.free()
    ret try emitCallSymbol(state, returnType, symbol, args, false, try declarationNoContext(declaration))
..

lowerArrayLength(state LoweringState*, array nt.Expr.Array*, args nt.NodeArray[nt.Expr*]) !$str:
    if array.inferLength:
        ret try strconv.formatUint(args.count())
    ..
    if array.length == none:
        throw "array constructor has no length"
    ..
    lengthValue := try emitExpr(state, array.length)
    defer lengthValue.free()
    sourceType := try typeName(try expressionType(array.length))
    defer sourceType.free()
    if strings.compare(sourceType, "i64"):
        ret try strings.copy(lengthValue)
    ..
    castId := try strconv.formatUint(state.nextValue)
    defer castId.free()
    state.nextValue = state.nextValue + 1
    opcode := "zext"
    if not checker.isUnsignedType(try expressionType(array.length)):
        opcode = "sext"
    ..
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(castId)
    try state.output.appendBorrowed(" = ")
    try state.output.appendCopy(opcode)
    try state.output.appendBorrowed(" ")
    try state.output.appendCopy(sourceType)
    try state.output.appendBorrowed(" ")
    try state.output.appendCopy(lengthValue)
    try state.output.appendBorrowed(" to i64\n")
    ret try strings.concat("%v", castId)
..

emitArrayConstructor(state LoweringState*, array nt.Expr.Array*, args nt.NodeArray[nt.Expr*]) !$str:
    elementType := try loweredTypeName(state, array.type)
    defer elementType.free()
    lengthValue := try lowerArrayLength(state, array, args)
    defer lengthValue.free()
    storageId := try strconv.formatUint(state.nextValue)
    defer storageId.free()
    state.nextValue = state.nextValue + 1
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(storageId)
    try state.output.appendBorrowed(" = alloca ")
    try state.output.appendCopy(elementType)
    try state.output.appendBorrowed(", i64 ")
    try state.output.appendCopy(lengthValue)
    try state.output.appendBorrowed("\n")
    if array.resolvedIndices.count() != args.count():
        throw "checked array constructor has an incomplete index map"
    ..
    for i := 0 to args.count():
        argumentExpr := try args.get(i)
        indexValue := try strconv.formatUint(try array.resolvedIndices.get(i))
        defer indexValue.free()
        valueExpr := argumentExpr
        argumentNode := nt.loadExpressionNode(argumentExpr)
        match addrof argumentNode as argument:
        case nt.Expr.Assign:
            valueExpr = argument.expr
        else:
            valueExpr = argumentExpr
        ..
        pointerId := try strconv.formatUint(state.nextValue)
        defer pointerId.free()
        state.nextValue = state.nextValue + 1
        value := try emitExpr(state, valueExpr)
        defer value.free()
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(pointerId)
        try state.output.appendBorrowed(" = getelementptr ")
        try state.output.appendCopy(elementType)
        try state.output.appendBorrowed(", ptr %v")
        try state.output.appendCopy(storageId)
        try state.output.appendBorrowed(", i64 ")
        try state.output.appendCopy(indexValue)
        try state.output.appendBorrowed("\n  store ")
        try state.output.appendCopy(elementType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(value)
        try state.output.appendBorrowed(", ptr %v")
        try state.output.appendCopy(pointerId)
        try state.output.appendBorrowed("\n")
    ..
    pointerFieldId := try strconv.formatUint(state.nextValue)
    defer pointerFieldId.free()
    state.nextValue = state.nextValue + 1
    countFieldId := try strconv.formatUint(state.nextValue)
    defer countFieldId.free()
    state.nextValue = state.nextValue + 1
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(pointerFieldId)
    try state.output.appendBorrowed(" = insertvalue %type.slice zeroinitializer, ptr %v")
    try state.output.appendCopy(storageId)
    try state.output.appendBorrowed(", 0\n  %v")
    try state.output.appendCopy(countFieldId)
    try state.output.appendBorrowed(" = insertvalue %type.slice %v")
    try state.output.appendCopy(pointerFieldId)
    try state.output.appendBorrowed(", i64 ")
    try state.output.appendCopy(lengthValue)
    try state.output.appendBorrowed(", 1\n")
    ret try strings.concat("%v", countFieldId)
..

emitCallSymbol(state LoweringState*, returnType nt.Type*, symbol str, args nt.NodeArray[nt.Expr*], indirect bool, noContext bool) !$str:
    resultType := try typeName(returnType)
    defer resultType.free()
    loweredArguments := try lowerCallArguments(state, args)
    defer loweredArguments.free()
    resultId := try strconv.formatUint(state.nextValue)
    defer resultId.free()
    isVoid := strings.compare(resultType, "void")
    if not isVoid:
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(resultId)
        try state.output.appendBorrowed(" = ")
    else:
        try state.output.appendBorrowed("  ")
    ..
    try state.output.appendBorrowed("call ")
    try state.output.appendCopy(resultType)
    try state.output.appendBorrowed(" ")
    if not indirect:
        try state.output.appendBorrowed("@")
    ..
    try state.output.appendCopy(symbol)
    try state.output.appendBorrowed("(")
    hasArgument := false
    if not noContext:
        try state.output.appendBorrowed("ptr ")
        try appendContextPointer(state.output, state)
        hasArgument = true
    ..
    for i := 0 to args.count():
        if hasArgument:
            try state.output.appendBorrowed(", ")
        ..
        argumentExpr := try args.get(i)
        try appendType(state.output, try expressionType(argumentExpr))
        try state.output.appendBorrowed(" ")
        argument := try loweredArguments.get(i)
        try state.output.appendCopy(argument)
        hasArgument = true
    ..
    try state.output.appendBorrowed(")\n")
    if isVoid:
        ret try strings.copy("")
    ..
    state.nextValue = state.nextValue + 1
    ret try strings.concat("%v", resultId)
..

emitProtoMethodCall(state LoweringState*, callOwner nt.Expr*, returnType nt.Type*, args nt.NodeArray[nt.Expr*]) !$str:
    callNode := nt.loadExpressionNode(callOwner)
    match addrof callNode as access:
    case nt.Expr.MemberAccess:
        memberNode := nt.loadExpressionNode(access.member)
        match addrof memberNode as member:
        case nt.Expr.Named:
            if member.decl == none:
                throw "unresolved protocol method in LLVM lowering"
            ..
            ownerType := try expressionType(access.owner)
            prototype := try structDeclaration(ownerType)
            match prototype.kind as protoKind:
            case dclr.DeclKind.Proto:
                if member.decl.methodOwnerType == none:
                    throw "resolved protocol method has no checked owner"
                ..
                if not sameDeclarationIdentity(try structDeclaration(member.decl.methodOwnerType), prototype):
                    throw "resolved protocol method belongs to a different prototype"
                ..
                methodIndex := member.decl.protoMethodIndex
                methodNoContext := member.decl.methodNoContext
                methodCount := try strconv.formatUint(protoKind.methods.count())
                defer methodCount.free()
                indexText := try strconv.formatUint(methodIndex)
                defer indexText.free()
                protoType := ownerType
                match ownerType as ownerKind:
                case nt.Type.Pointer:
                    protoType = ownerKind.toType
                else:
                    protoType = ownerType
                ..
                protoTypeName := try typeName(protoType)
                defer protoTypeName.free()
                protoValue str
                match ownerType as ownerKind:
                case nt.Type.Pointer:
                    protoAddress := try emitExpr(state, access.owner)
                    defer protoAddress.free()
                    loadedId := try strconv.formatUint(state.nextValue)
                    defer loadedId.free()
                    state.nextValue = state.nextValue + 1
                    try state.output.appendBorrowed("  %v")
                    try state.output.appendCopy(loadedId)
                    try state.output.appendBorrowed(" = load ")
                    try state.output.appendCopy(protoTypeName)
                    try state.output.appendBorrowed(", ptr ")
                    try state.output.appendCopy(protoAddress)
                    try state.output.appendBorrowed("\n")
                    protoValue = try strings.concat("%v", loadedId)
                else:
                    protoValue = try emitExpr(state, access.owner)
                ..
                defer protoValue.free()
                vtableId := try strconv.formatUint(state.nextValue)
                defer vtableId.free()
                state.nextValue = state.nextValue + 1
                slotId := try strconv.formatUint(state.nextValue)
                defer slotId.free()
                state.nextValue = state.nextValue + 1
                functionId := try strconv.formatUint(state.nextValue)
                defer functionId.free()
                state.nextValue = state.nextValue + 1
                implementationId := try strconv.formatUint(state.nextValue)
                defer implementationId.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(vtableId)
                try state.output.appendBorrowed(" = extractvalue ")
                try state.output.appendCopy(protoTypeName)
                try state.output.appendBorrowed(" ")
                try state.output.appendCopy(protoValue)
                try state.output.appendBorrowed(", 0\n  %v")
                try state.output.appendCopy(slotId)
                try state.output.appendBorrowed(" = getelementptr [")
                try state.output.appendCopy(methodCount)
                try state.output.appendBorrowed(" x ptr], ptr %v")
                try state.output.appendCopy(vtableId)
                try state.output.appendBorrowed(", i32 0, i32 ")
                try state.output.appendCopy(indexText)
                try state.output.appendBorrowed("\n  %v")
                try state.output.appendCopy(functionId)
                try state.output.appendBorrowed(" = load ptr, ptr %v")
                try state.output.appendCopy(slotId)
                try state.output.appendBorrowed("\n  %v")
                try state.output.appendCopy(implementationId)
                try state.output.appendBorrowed(" = extractvalue ")
                try state.output.appendCopy(protoTypeName)
                try state.output.appendBorrowed(" ")
                try state.output.appendCopy(protoValue)
                try state.output.appendBorrowed(", 1\n")
                loweredArguments := try lowerCallArguments(state, args)
                defer loweredArguments.free()
                resultType := try typeName(returnType)
                defer resultType.free()
                isVoid := strings.compare(resultType, "void")
                resultId := try strconv.formatUint(state.nextValue)
                defer resultId.free()
                if not isVoid:
                    try state.output.appendBorrowed("  %v")
                    try state.output.appendCopy(resultId)
                    try state.output.appendBorrowed(" = ")
                else:
                    try state.output.appendBorrowed("  ")
                ..
                try state.output.appendBorrowed("call ")
                try state.output.appendCopy(resultType)
                try state.output.appendBorrowed(" %v")
                try state.output.appendCopy(functionId)
                try state.output.appendBorrowed("(")
                hasArgument := false
                if not methodNoContext:
                    try state.output.appendBorrowed("ptr ")
                    try appendContextPointer(state.output, state)
                    hasArgument = true
                ..
                if hasArgument:
                    try state.output.appendBorrowed(", ")
                ..
                try state.output.appendBorrowed("ptr %v")
                try state.output.appendCopy(implementationId)
                hasArgument = true
                for i := 0 to args.count():
                    argumentExpr := try args.get(i)
                    argumentValue := try loweredArguments.get(i)
                    if hasArgument:
                        try state.output.appendBorrowed(", ")
                    ..
                    try appendType(state.output, try expressionType(argumentExpr))
                    try state.output.appendBorrowed(" ")
                    try state.output.appendCopy(argumentValue)
                    hasArgument = true
                ..
                try state.output.appendBorrowed(")\n")
                if isVoid:
                    ret try strings.copy("")
                ..
                state.nextValue = state.nextValue + 1
                ret try strings.concat("%v", resultId)
            else:
                throw "member call owner is not a protocol value"
            ..
        else:
            throw "protocol call member is not a resolved name"
        ..
    else:
        throw "protocol call owner is not member access"
    ..
..

# Whether an expression names storage that can be passed to a pointer receiver.
# Calls on computed values still need a receiver address, but that address must
# point to a temporary containing the computed value rather than fail lowering.
isAssignableExpression(expression nt.Expr*) !bool:
    node := nt.loadExpressionNode(expression)
    match addrof node as value:
    case nt.Expr.Named:
        if value.category == nt.ValueCategory.Unresolved: throw "expression has no checked value category in LLVM lowering" ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.MemberAccess:
        if value.category == nt.ValueCategory.Unresolved: throw "expression has no checked value category in LLVM lowering" ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.Subscript:
        if value.category == nt.ValueCategory.Unresolved: throw "expression has no checked value category in LLVM lowering" ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.Unary:
        if value.category == nt.ValueCategory.Unresolved:
            throw "expression has no checked value category in LLVM lowering"
        ..
        ret value.category == nt.ValueCategory.Place
    else:
        ret false
    ..
..

emitStaticMethodCall(state LoweringState*, callOwner nt.Expr*, returnType nt.Type*, args nt.NodeArray[nt.Expr*], typeArgs nt.NodeArray[nt.Type*]) !$str:
    callNode := nt.loadExpressionNode(callOwner)
    match addrof callNode as genericOwner:
    case nt.Expr.GenericApply:
        callOwner = genericOwner.owner
        callNode = nt.loadExpressionNode(callOwner)
    else:
        callNode = callNode
    ..
    match addrof callNode as access:
    case nt.Expr.MemberAccess:
        memberNode := nt.loadExpressionNode(access.member)
        match addrof memberNode as member:
        case nt.Expr.Named:
            declaration := member.decl
            if declaration == none:
                throw "static method call has no checked declaration in LLVM lowering"
            ..
            receiver := try methodReceiver(declaration)
            if receiver == none:
                throw "static method declaration has no receiver binding"
            ..
            receiverType nt.Type* = none
            match receiver.kind as receiverKind:
            case dclr.DeclKind.Argument:
                receiverType = receiverKind.type
            case dclr.DeclKind.Variable:
                receiverType = receiverKind.type
            else:
                throw "static method receiver has no value type"
            ..
            if receiverType == none:
                throw "static method receiver has no checked type"
            ..
            actualOwnerType := try expressionType(access.owner)
            concreteReceiverType := try loweredConcreteType(state, actualOwnerType)
            match receiverType as formalReceiverKind:
            case nt.Type.Pointer:
                match concreteReceiverType as actualReceiverKind:
                case nt.Type.Pointer:
                    concreteReceiverType = concreteReceiverType
                else:
                    concreteReceiverType = try storeLoweredType(nt.Type.Pointer(toType=concreteReceiverType))
                ..
            else:
                concreteReceiverType = concreteReceiverType
            ..
            if concreteReceiverType == none:
                throw "static method receiver type is unresolved in this specialization"
            ..
            receiverValue str
            match receiverType as receiverTypeKind:
            case nt.Type.Pointer:
                ownerType := try expressionType(access.owner)
                match ownerType as ownerTypeKind:
                case nt.Type.Pointer:
                    receiverValue = try emitExpr(state, access.owner)
                else:
                    addressableReceiver := try isAssignableExpression(access.owner)
                    if addressableReceiver:
                        receiverValue = try emitLValuePointer(state, access.owner)
                    else:
                        receiverContents := try emitExpr(state, access.owner)
                        defer receiverContents.free()
                        receiverLlvmType := try typeName(ownerType)
                        defer receiverLlvmType.free()
                        slot := try strconv.formatUint(state.nextValue)
                        defer slot.free()
                        state.nextValue = state.nextValue + 1
                        try state.output.appendBorrowed("  %tmp.slot")
                        try state.output.appendCopy(slot)
                        try state.output.appendBorrowed(" = alloca ")
                        try state.output.appendCopy(receiverLlvmType)
                        try state.output.appendBorrowed("\n  store ")
                        try state.output.appendCopy(receiverLlvmType)
                        try state.output.appendBorrowed(" ")
                        try state.output.appendCopy(receiverContents)
                        try state.output.appendBorrowed(", ptr %tmp.slot")
                        try state.output.appendCopy(slot)
                        try state.output.appendBorrowed("\n")
                        receiverValue = try strings.concat("%tmp.slot", slot)
                    ..
                ..
            else:
                receiverValue = try emitExpr(state, access.owner)
            ..
            defer receiverValue.free()
            symbol str
            match declaration.kind as methodKind:
            case dclr.DeclKind.Function:
                if typeArgs.count() != 0:
                    symbol = try loweredSpecializationSymbol(state, declaration, typeArgs)
                else:
                    if methodKind.typeParams.count() != 0:
                        throw "generic method call reached LLVM lowering without checked type arguments"
                    ..
                    symbol = try declarationLinkName(declaration)
                ..
            else:
                throw "static method declaration is not a function"
            ..
            defer symbol.free()
            loweredArguments := try lowerCallArguments(state, args)
            defer loweredArguments.free()
            resultType := try typeName(returnType)
            defer resultType.free()
            resultId := try strconv.formatUint(state.nextValue)
            defer resultId.free()
            isVoid := strings.compare(resultType, "void")
            if not isVoid:
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(resultId)
                try state.output.appendBorrowed(" = ")
            else:
                try state.output.appendBorrowed("  ")
            ..
            try state.output.appendBorrowed("call ")
            try state.output.appendCopy(resultType)
            try state.output.appendBorrowed(" @")
            try state.output.appendCopy(symbol)
            try state.output.appendBorrowed("(")
            noContext := try declarationNoContext(declaration)
            hasArgument := false
            if not noContext:
                try state.output.appendBorrowed("ptr ")
                try appendContextPointer(state.output, state)
                hasArgument = true
            ..
            if hasArgument:
                try state.output.appendBorrowed(", ")
            ..
            try appendType(state.output, concreteReceiverType)
            try state.output.appendBorrowed(" ")
            try state.output.appendCopy(receiverValue)
            for i := 0 to args.count():
                argumentExpr := try args.get(i)
                try state.output.appendBorrowed(", ")
                try appendType(state.output, try expressionType(argumentExpr))
                try state.output.appendBorrowed(" ")
                loweredArgument := try loweredArguments.get(i)
                try state.output.appendCopy(loweredArgument)
            ..
            try state.output.appendBorrowed(")\n")
            if isVoid:
                ret try strings.copy("")
            ..
            state.nextValue = state.nextValue + 1
            ret try strings.concat("%v", resultId)
        else:
            throw "static method call member is not a resolved name"
        ..
    else:
        throw "static method call owner is not member access"
    ..
..

emitProtoImplementation(state LoweringState*, callExpression nt.Expr*, resultType nt.Type*) !$str:
    callNode := nt.loadExpressionNode(callExpression)
    match addrof callNode as genericCall:
    case nt.Expr.GenericApply:
        callNode = nt.loadExpressionNode(genericCall.owner)
    else:
        callNode = callNode
    ..
    match addrof callNode as access:
    case nt.Expr.MemberAccess:
        sourceType := try expressionType(access.owner)
        sourceValue := try emitExpr(state, access.owner)
        defer sourceValue.free()
        aggregateType nt.Type* = sourceType
        aggregateValue := try strings.copy(sourceValue)
        defer aggregateValue.free()
        match sourceType as sourceKind:
        case nt.Type.Pointer:
            aggregateType = sourceKind.toType
            aggregateTypeName := try loweredTypeName(state, aggregateType)
            defer aggregateTypeName.free()
            loadedId := try strconv.formatUint(state.nextValue)
            defer loadedId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(loadedId)
            try state.output.appendBorrowed(" = load ")
            try state.output.appendCopy(aggregateTypeName)
            try state.output.appendBorrowed(", ptr ")
            try state.output.appendCopy(sourceValue)
            try state.output.appendBorrowed("\n")
            aggregateValue.free()
            aggregateValue = try strings.concat("%v", loadedId)
        else:
            aggregateType = aggregateType
        ..
        sourceTypeName := try loweredTypeName(state, aggregateType)
        defer sourceTypeName.free()
        pointerId := try strconv.formatUint(state.nextValue)
        defer pointerId.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(pointerId)
        try state.output.appendBorrowed(" = extractvalue ")
        try state.output.appendCopy(sourceTypeName)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(aggregateValue)
        try state.output.appendBorrowed(", 1\n")
        innerResult := try throwingValueType(resultType)
        innerTypeName := try loweredTypeName(state, innerResult)
        defer innerTypeName.free()
        payload str
        match innerResult as resultKind:
        case nt.Type.Pointer:
            payload = try strings.concat("%v", pointerId)
        else:
            loadedId := try strconv.formatUint(state.nextValue)
            defer loadedId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(loadedId)
            try state.output.appendBorrowed(" = load ")
            try state.output.appendCopy(innerTypeName)
            try state.output.appendBorrowed(", ptr %v")
            try state.output.appendCopy(pointerId)
            try state.output.appendBorrowed("\n")
            payload = try strings.concat("%v", loadedId)
        ..
        defer payload.free()
        resultAggregateType := try typeName(resultType)
        defer resultAggregateType.free()
        aggregateId := try strconv.formatUint(state.nextValue)
        defer aggregateId.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(aggregateId)
        try state.output.appendBorrowed(" = insertvalue ")
        try state.output.appendCopy(resultAggregateType)
        try state.output.appendBorrowed(" zeroinitializer, ")
        try state.output.appendCopy(innerTypeName)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(payload)
        try state.output.appendBorrowed(", 1\n")
        ret try strings.concat("%v", aggregateId)
    else:
        throw "prototype implementation operation requires member access"
    ..
..

isAddressableExpression(expression nt.Expr*) !bool:
    node := nt.loadExpressionNode(expression)
    match addrof node as value:
    case nt.Expr.Named:
        if value.category == nt.ValueCategory.Unresolved:
            throw "named expression has no checked addressability"
        ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.MemberAccess:
        if value.category == nt.ValueCategory.Unresolved:
            throw "member expression has no checked addressability"
        ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.Subscript:
        if value.category == nt.ValueCategory.Unresolved:
            throw "subscript expression has no checked addressability"
        ..
        ret value.category == nt.ValueCategory.Place
    case nt.Expr.Unary:
        if value.category == nt.ValueCategory.Unresolved:
            throw "unary expression has no checked addressability"
        ..
        ret value.category == nt.ValueCategory.Place
    else:
        ret false
    ..
..

emitProtoView(state LoweringState*, callExpression nt.Expr*, viewType nt.Type*) !$str:
    callNode := nt.loadExpressionNode(callExpression)
    match addrof callNode as call:
    case nt.Expr.MemberAccess:
        viewTypeName := try typeName(viewType)
        defer viewTypeName.free()
        # Borrowing an implementation value needs its storage address. A
        # pointer receiver (implBorrow) already evaluates to that address and
        # must not be replaced with the address of the pointer's local slot.
        receiverType := try expressionType(call.owner)
        implementation str
        match receiverType as receiverKind:
        case nt.Type.Pointer:
            implementation = try emitExpr(state, call.owner)
        else:
            if try isAddressableExpression(call.owner):
                implementation = try emitLValuePointer(state, call.owner)
            else:
                receiverValue := try emitExpr(state, call.owner)
                defer receiverValue.free()
                receiverTypeName := try loweredTypeName(state, receiverType)
                defer receiverTypeName.free()
                storageId := try strconv.formatUint(state.nextValue)
                defer storageId.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(storageId)
                try state.output.appendBorrowed(" = alloca ")
                try state.output.appendCopy(receiverTypeName)
                try state.output.appendBorrowed("\n  store ")
                try state.output.appendCopy(receiverTypeName)
                try state.output.appendBorrowed(" ")
                try state.output.appendCopy(receiverValue)
                try state.output.appendBorrowed(", ptr %v")
                try state.output.appendCopy(storageId)
                try state.output.appendBorrowed("\n")
                implementation = try strings.concat("%v", storageId)
            ..
        ..
        defer implementation.free()
        vtableId := try strconv.formatUint(state.nextValue)
        defer vtableId.free()
        state.nextValue = state.nextValue + 1
        implementationId := try strconv.formatUint(state.nextValue)
        defer implementationId.free()
        state.nextValue = state.nextValue + 1
        implementationType := try expressionType(call.owner)
        implementationDecl := try structDeclaration(implementationType)
        prototypeDecl := try structDeclaration(viewType)
        vtable := try protoVTableSymbol(implementationDecl, prototypeDecl)
        defer vtable.free()
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(vtableId)
        try state.output.appendBorrowed(" = insertvalue ")
        try state.output.appendCopy(viewTypeName)
        try state.output.appendBorrowed(" zeroinitializer, ptr @")
        try state.output.appendCopy(vtable)
        try state.output.appendBorrowed(", 0\n  %v")
        try state.output.appendCopy(implementationId)
        try state.output.appendBorrowed(" = insertvalue ")
        try state.output.appendCopy(viewTypeName)
        try state.output.appendBorrowed(" %v")
        try state.output.appendCopy(vtableId)
        try state.output.appendBorrowed(", ptr ")
        try state.output.appendCopy(implementation)
        try state.output.appendBorrowed(", 1\n")
        ret try strings.concat("%v", implementationId)
    else:
        throw "prototype view operation has no implementation receiver"
    ..
..

constructorFieldType(ownerType nt.Type*, index u64, declaredType nt.Type*) !nt.Type*:
    match ownerType as concreteOwner:
    case nt.Type.Templated:
        header := try specializedStructHeader(ownerType)
        field := nt.loadExpressionNode(try header.fields.get(index))
        match addrof field as concreteField:
        case nt.Expr.VarDef:
            ret concreteField.type
        else:
            throw "specialized structure field has no checked type"
        ..
    else:
        ret declaredType
    ..
..

emitStructConstructor(state LoweringState*, resultType nt.Type*, declaration dclr.Decl*, args nt.NodeArray[nt.Expr*]) !$str:
    # Checked constructor expressions inside a generic body retain the source
    # template's type nodes. Resolve those against this emitted specialization
    # before asking for either the LLVM name or the owning declaration.
    concreteResultType := try loweredConcreteType(state, resultType)
    loweredType := try typeName(concreteResultType)
    defer loweredType.free()
    hasAggregate := false
    lastAggregateId u64 = 0
    for i := 0 to args.count():
        argumentExpr := try args.get(i)
        argumentValue := argumentExpr
        argumentNode := nt.loadExpressionNode(argumentExpr)
        fieldIndexValue u64 = i
        match addrof argumentNode as argument:
        case nt.Expr.Assign:
            argumentValue = argument.expr
            if not argument.hasResolvedFieldIndex:
                throw "struct constructor has an unresolved field index"
            ..
            fieldIndexValue = argument.resolvedFieldIndex
        else:
            fieldIndexValue = i
        ..
        value := try emitExpr(state, argumentValue)
        defer value.free()
        insertionValue := try strings.copy(value)
        defer insertionValue.free()
        valueTypeNode := try expressionType(argumentValue)
        structureDeclaration := try structDeclaration(concreteResultType)
        match structureDeclaration.kind as structureKind:
        case dclr.DeclKind.Struct:
            fieldDeclaration := try structureKind.fields.get(fieldIndexValue)
            match fieldDeclaration.kind as fieldKind:
            case dclr.DeclKind.Field:
                expectedFieldTypeNode := try constructorFieldType(concreteResultType, fieldIndexValue, fieldKind.type)
                sourceFieldType := try loweredTypeName(state, valueTypeNode)
                defer sourceFieldType.free()
                expectedFieldType := try loweredTypeName(state, expectedFieldTypeNode)
                defer expectedFieldType.free()
                # Named integer types (u16/u64 and aliases) still need LLVM
                # integer coercion. Decide from their lowered widths instead
                # of skipping every named type here.
                coerced str, conversionError error = coerceIntegerValue(state, value, valueTypeNode, expectedFieldTypeNode)
                if conversionError.nok():
                    insertionValue.free()
                    throw conversionError
                ..
                insertionValue.free()
                insertionValue = coerced
                valueTypeNode = expectedFieldTypeNode
            else:
                throw "structure initializer field has no type"
            ..
        else:
            structureDeclaration = structureDeclaration
        ..
        valueType := try loweredTypeName(state, valueTypeNode)
        defer valueType.free()
        currentAggregateId := state.nextValue
        id := try strconv.formatUint(state.nextValue)
        defer id.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(id)
        try state.output.appendBorrowed(" = insertvalue ")
        try state.output.appendCopy(loweredType)
        try state.output.appendBorrowed(" ")
        if not hasAggregate:
            try state.output.appendBorrowed("zeroinitializer")
        else:
            priorId := try strconv.formatUint(lastAggregateId)
            defer priorId.free()
            try state.output.appendBorrowed("%v")
            try state.output.appendCopy(priorId)
        ..
        indexText := try strconv.formatUint(fieldIndexValue)
        defer indexText.free()
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(valueType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(insertionValue)
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(indexText)
        try state.output.appendBorrowed("\n")
        lastAggregateId = currentAggregateId
        hasAggregate = true
    ..
    if args.count() == 0:
        ret try strings.copy("zeroinitializer")
    ..
    lastId := try strconv.formatUint(lastAggregateId)
    defer lastId.free()
    ret try strings.concat("%v", lastId)
..

emitUnionVariantConstructor(state LoweringState*, resultType nt.Type*, declaration dclr.Decl*, args nt.NodeArray[nt.Expr*]) !$str:
    info := try unionVariantInfo(declaration)
    unionType := try typeName(resultType)
    defer unionType.free()
    variantSymbol := try typeIdentity(declaration)
    defer variantSymbol.free()
    variantType := try strings.concat("%", variantSymbol)
    defer variantType.free()
    hasAggregate := false
    lastAggregateId u64 = 0
    match declaration.kind as variantKind:
    case dclr.DeclKind.UnionVariant:
        for i := 0 to args.count():
            argumentExpr := try args.get(i)
            argumentValue := argumentExpr
            argumentNode := nt.loadExpressionNode(argumentExpr)
            fieldIndexValue u64 = i
            match addrof argumentNode as argument:
            case nt.Expr.Assign:
                argumentValue = argument.expr
                if not argument.hasResolvedFieldIndex:
                    throw "union constructor has an unresolved field index"
                ..
                fieldIndexValue = argument.resolvedFieldIndex
            else:
                fieldIndexValue = i
            ..
            value := try emitExpr(state, argumentValue)
            defer value.free()
            valueType := try typeName(try expressionType(argumentValue))
            defer valueType.free()
            currentAggregateId := state.nextValue
            id := try strconv.formatUint(state.nextValue)
            defer id.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(id)
            try state.output.appendBorrowed(" = insertvalue ")
            try state.output.appendCopy(variantType)
            try state.output.appendBorrowed(" ")
            if not hasAggregate:
                try state.output.appendBorrowed("zeroinitializer")
            else:
                priorId := try strconv.formatUint(lastAggregateId)
                defer priorId.free()
                try state.output.appendBorrowed("%v")
                try state.output.appendCopy(priorId)
            ..
            indexText := try strconv.formatUint(fieldIndexValue)
            defer indexText.free()
            try state.output.appendBorrowed(", ")
            try state.output.appendCopy(valueType)
            try state.output.appendBorrowed(" ")
            try state.output.appendCopy(value)
            try state.output.appendBorrowed(", ")
            try state.output.appendCopy(indexText)
            try state.output.appendBorrowed("\n")
            lastAggregateId = currentAggregateId
            hasAggregate = true
        ..
    else:
        throw "union constructor target is not a variant"
    ..
    storageId := try strconv.formatUint(state.nextValue)
    defer storageId.free()
    state.nextValue = state.nextValue + 1
    tagPointerId := try strconv.formatUint(state.nextValue)
    defer tagPointerId.free()
    state.nextValue = state.nextValue + 1
    payloadPointerId := try strconv.formatUint(state.nextValue)
    defer payloadPointerId.free()
    state.nextValue = state.nextValue + 1
    resultId := try strconv.formatUint(state.nextValue)
    defer resultId.free()
    state.nextValue = state.nextValue + 1
    tag := try strconv.formatUint(info.tag)
    defer tag.free()
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(storageId)
    try state.output.appendBorrowed(" = alloca ")
    try state.output.appendCopy(unionType)
    try state.output.appendBorrowed("\n  %v")
    try state.output.appendCopy(tagPointerId)
    try state.output.appendBorrowed(" = getelementptr ")
    try state.output.appendCopy(unionType)
    try state.output.appendBorrowed(", ptr %v")
    try state.output.appendCopy(storageId)
    try state.output.appendBorrowed(", i32 0, i32 0\n  store i32 ")
    try state.output.appendCopy(tag)
    try state.output.appendBorrowed(", ptr %v")
    try state.output.appendCopy(tagPointerId)
    try state.output.appendBorrowed("\n  %v")
    try state.output.appendCopy(payloadPointerId)
    try state.output.appendBorrowed(" = getelementptr ")
    try state.output.appendCopy(unionType)
    try state.output.appendBorrowed(", ptr %v")
    try state.output.appendCopy(storageId)
    try state.output.appendBorrowed(", i32 0, i32 2\n  store ")
    try state.output.appendCopy(variantType)
    try state.output.appendBorrowed(" ")
    if args.count() == 0:
        try state.output.appendBorrowed("zeroinitializer")
    else:
        aggregateId := try strconv.formatUint(lastAggregateId)
        defer aggregateId.free()
        try state.output.appendBorrowed("%v")
        try state.output.appendCopy(aggregateId)
    ..
    try state.output.appendBorrowed(", ptr %v")
    try state.output.appendCopy(payloadPointerId)
    try state.output.appendBorrowed("\n  %v")
    try state.output.appendCopy(resultId)
    try state.output.appendBorrowed(" = load ")
    try state.output.appendCopy(unionType)
    try state.output.appendBorrowed(", ptr %v")
    try state.output.appendCopy(storageId)
    try state.output.appendBorrowed("\n")
    ret try strings.concat("%v", resultId)
..

emitTry(state LoweringState*, call nt.Expr*) !$str:
    callType := try expressionType(call)
    if not isThrowingType(callType):
        throw "try expression does not wrap a throwing call"
    ..
    callValue := try emitExpr(state, call)
    defer callValue.free()
    aggregateType := try typeName(callType)
    defer aggregateType.free()
    errorValueId := try strconv.formatUint(state.nextValue)
    defer errorValueId.free()
    state.nextValue = state.nextValue + 1
    errorCodeId := try strconv.formatUint(state.nextValue)
    defer errorCodeId.free()
    state.nextValue = state.nextValue + 1
    failedId := try strconv.formatUint(state.nextValue)
    defer failedId.free()
    state.nextValue = state.nextValue + 1
    branchId := try strconv.formatUint(state.nextBlock)
    defer branchId.free()
    state.nextBlock = state.nextBlock + 1
    failedLabel := try strings.concat("try_failed_", branchId)
    defer failedLabel.free()
    successLabel := try strings.concat("try_success_", branchId)
    defer successLabel.free()
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(errorValueId)
    try state.output.appendBorrowed(" = extractvalue ")
    try state.output.appendCopy(aggregateType)
    try state.output.appendBorrowed(" ")
    try state.output.appendCopy(callValue)
    try state.output.appendBorrowed(", 0\n  %v")
    try state.output.appendCopy(errorCodeId)
    try state.output.appendBorrowed(" = extractvalue %type.error %v")
    try state.output.appendCopy(errorValueId)
    try state.output.appendBorrowed(", 1\n  %v")
    try state.output.appendCopy(failedId)
    try state.output.appendBorrowed(" = icmp ne i32 %v")
    try state.output.appendCopy(errorCodeId)
    try state.output.appendBorrowed(", 0\n  br i1 %v")
    try state.output.appendCopy(failedId)
    try state.output.appendBorrowed(", label %")
    try state.output.appendCopy(failedLabel)
    try state.output.appendBorrowed(", label %")
    try state.output.appendCopy(successLabel)
    try state.output.appendBorrowed("\n")
    try state.output.appendCopy(failedLabel)
    try state.output.appendBorrowed(":\n")
    activeDefers := state.deferFrame
    snapshot := activeDefers
    loop snapshot != none:
        snapshot.savedCount = snapshot.activeCount
        snapshot = snapshot.parent
    ..
    try emitDefersUntil(state, none, true)
    returnType := try typeName(state.returnType)
    defer returnType.free()
    propagated := try strconv.formatUint(state.nextValue)
    defer propagated.free()
    state.nextValue = state.nextValue + 1
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(propagated)
    try state.output.appendBorrowed(" = insertvalue ")
    try state.output.appendCopy(returnType)
    try state.output.appendBorrowed(" zeroinitializer, %type.error %v")
    try state.output.appendCopy(errorValueId)
    try state.output.appendBorrowed(", 0\n  ret ")
    try state.output.appendCopy(returnType)
    try state.output.appendBorrowed(" %v")
    try state.output.appendCopy(propagated)
    try state.output.appendBorrowed("\n")
    snapshot = activeDefers
    loop snapshot != none:
        snapshot.activeCount = snapshot.savedCount
        snapshot = snapshot.parent
    ..
    state.deferFrame = activeDefers
    try state.output.appendCopy(successLabel)
    try state.output.appendBorrowed(":\n")
    try setCurrentBlock(state, successLabel)
    resultType := try throwingValueType(callType)
    if try isVoidType(resultType):
        ret try strings.copy("")
    ..
    loweredResultType := try typeName(resultType)
    defer loweredResultType.free()
    resultId := try strconv.formatUint(state.nextValue)
    defer resultId.free()
    state.nextValue = state.nextValue + 1
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(resultId)
    try state.output.appendBorrowed(" = extractvalue ")
    try state.output.appendCopy(aggregateType)
    try state.output.appendBorrowed(" ")
    try state.output.appendCopy(callValue)
    try state.output.appendBorrowed(", 1\n")
    ret try strings.concat("%v", resultId)
..

emitThrow(state LoweringState*, expression nt.Expr*) !void:
    if not isThrowingType(state.returnType):
        throw "throw escaped semantic checking in a non-throwing function"
    ..
    thrown := try emitExpr(state, expression)
    defer thrown.free()
    thrownType := try expressionType(expression)
    loweredThrownType := try typeName(thrownType)
    defer loweredThrownType.free()
    errorValue $str
    if strings.compare(loweredThrownType, "%type.error"):
        errorValue = try strings.copy(thrown)
    elif strings.compare(loweredThrownType, "%type.str"):
        messagePointerId := try strconv.formatUint(state.nextValue)
        defer messagePointerId.free()
        state.nextValue = state.nextValue + 1
        messageLengthId := try strconv.formatUint(state.nextValue)
        defer messageLengthId.free()
        state.nextValue = state.nextValue + 1
        tooLongId := try strconv.formatUint(state.nextValue)
        defer tooLongId.free()
        state.nextValue = state.nextValue + 1
        clampedLengthId := try strconv.formatUint(state.nextValue)
        defer clampedLengthId.free()
        state.nextValue = state.nextValue + 1
        shortLengthId := try strconv.formatUint(state.nextValue)
        defer shortLengthId.free()
        state.nextValue = state.nextValue + 1
        messageId := try strconv.formatUint(state.nextValue)
        defer messageId.free()
        state.nextValue = state.nextValue + 1
        codeId := try strconv.formatUint(state.nextValue)
        defer codeId.free()
        state.nextValue = state.nextValue + 1
        traceId := try strconv.formatUint(state.nextValue)
        defer traceId.free()
        state.nextValue = state.nextValue + 1
        lengthFieldId := try strconv.formatUint(state.nextValue)
        defer lengthFieldId.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(messagePointerId)
        try state.output.appendBorrowed(" = extractvalue %type.str ")
        try state.output.appendCopy(thrown)
        try state.output.appendBorrowed(", 0\n  %v")
        try state.output.appendCopy(messageLengthId)
        try state.output.appendBorrowed(" = extractvalue %type.str ")
        try state.output.appendCopy(thrown)
        try state.output.appendBorrowed(", 1\n  %v")
        try state.output.appendCopy(tooLongId)
        try state.output.appendBorrowed(" = icmp ugt i64 %v")
        try state.output.appendCopy(messageLengthId)
        try state.output.appendBorrowed(", 65535\n  %v")
        try state.output.appendCopy(clampedLengthId)
        try state.output.appendBorrowed(" = select i1 %v")
        try state.output.appendCopy(tooLongId)
        try state.output.appendBorrowed(", i64 65535, i64 %v")
        try state.output.appendCopy(messageLengthId)
        try state.output.appendBorrowed("\n  %v")
        try state.output.appendCopy(shortLengthId)
        try state.output.appendBorrowed(" = trunc i64 %v")
        try state.output.appendCopy(clampedLengthId)
        try state.output.appendBorrowed(" to i16\n  %v")
        try state.output.appendCopy(messageId)
        try state.output.appendBorrowed(" = insertvalue %type.error zeroinitializer, ptr %v")
        try state.output.appendCopy(messagePointerId)
        try state.output.appendBorrowed(", 0\n  %v")
        try state.output.appendCopy(codeId)
        try state.output.appendBorrowed(" = insertvalue %type.error %v")
        try state.output.appendCopy(messageId)
        try state.output.appendBorrowed(", i32 1, 1\n  %v")
        try state.output.appendCopy(traceId)
        try state.output.appendBorrowed(" = insertvalue %type.error %v")
        try state.output.appendCopy(codeId)
        try state.output.appendBorrowed(", i16 0, 2\n  %v")
        try state.output.appendCopy(lengthFieldId)
        try state.output.appendBorrowed(" = insertvalue %type.error %v")
        try state.output.appendCopy(traceId)
        try state.output.appendBorrowed(", i16 %v")
        try state.output.appendCopy(shortLengthId)
        try state.output.appendBorrowed(", 3\n")
        errorValue = try strings.concat("%v", lengthFieldId)
    else:
        throw "throw requires an error or string value"
    ..
    defer errorValue.free()
    try emitDefersUntil(state, none, true)
    resultType := try typeName(state.returnType)
    defer resultType.free()
    resultId := try strconv.formatUint(state.nextValue)
    defer resultId.free()
    state.nextValue = state.nextValue + 1
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(resultId)
    try state.output.appendBorrowed(" = insertvalue ")
    try state.output.appendCopy(resultType)
    try state.output.appendBorrowed(" zeroinitializer, %type.error ")
    try state.output.appendCopy(errorValue)
    try state.output.appendBorrowed(", 0\n  ret ")
    try state.output.appendCopy(resultType)
    try state.output.appendBorrowed(" %v")
    try state.output.appendCopy(resultId)
    try state.output.appendBorrowed("\n")
..

emitLogicalBinary(state LoweringState*, operation u8, leftExpr nt.Expr*, rightExpr nt.Expr*) !$str:
    left := try emitExpr(state, leftExpr)
    defer left.free()
    leftBlock := try strings.copy(state.currentBlock)
    defer leftBlock.free()
    id := try strconv.formatUint(state.nextBlock)
    defer id.free()
    state.nextBlock = state.nextBlock + 1
    rhsLabel := try strings.concat("logic_rhs_", id)
    defer rhsLabel.free()
    endLabel := try strings.concat("logic_end_", id)
    defer endLabel.free()
    try state.output.appendBorrowed("  br i1 ")
    try state.output.appendCopy(left)
    if operation == tokens.KwType.ANDAND:
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(rhsLabel)
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(endLabel)
    else:
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(endLabel)
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(rhsLabel)
    ..
    try state.output.appendBorrowed("\n")
    try state.output.appendCopy(rhsLabel)
    try state.output.appendBorrowed(":\n")
    try setCurrentBlock(state, rhsLabel)
    right := try emitExpr(state, rightExpr)
    defer right.free()
    rightBlock := try strings.copy(state.currentBlock)
    defer rightBlock.free()
    try state.output.appendBorrowed("  br label %")
    try state.output.appendCopy(endLabel)
    try state.output.appendBorrowed("\n")
    try state.output.appendCopy(endLabel)
    try state.output.appendBorrowed(":\n")
    try setCurrentBlock(state, endLabel)
    resultId := try strconv.formatUint(state.nextValue)
    defer resultId.free()
    state.nextValue = state.nextValue + 1
    shortValue str
    if operation == tokens.KwType.ANDAND:
        shortValue = "false"
    else:
        shortValue = "true"
    ..
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(resultId)
    try state.output.appendBorrowed(" = phi i1 [ ")
    try state.output.appendCopy(shortValue)
    try state.output.appendBorrowed(", %")
    try state.output.appendCopy(leftBlock)
    try state.output.appendBorrowed(" ], [ ")
    try state.output.appendCopy(right)
    try state.output.appendBorrowed(", %")
    try state.output.appendCopy(rightBlock)
    try state.output.appendBorrowed(" ]\n")
    ret try strings.concat("%v", resultId)
..

emitProtoEquality(state LoweringState*, prototypeType nt.Type*, left str, right str, negate bool) !$str:
    lowered := try typeName(prototypeType)
    defer lowered.free()
    comparison0Id u64 = 0
    comparison1Id u64 = 0
    for protoFieldIndex u64 = 0 to 2:
        leftId := try strconv.formatUint(state.nextValue)
        defer leftId.free()
        state.nextValue = state.nextValue + 1
        rightId := try strconv.formatUint(state.nextValue)
        defer rightId.free()
        state.nextValue = state.nextValue + 1
        compareValueId := state.nextValue
        compareId := try strconv.formatUint(compareValueId)
        defer compareId.free()
        state.nextValue = state.nextValue + 1
        index := try strconv.formatUint(protoFieldIndex)
        defer index.free()
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(leftId)
        try state.output.appendBorrowed(" = extractvalue ")
        try state.output.appendCopy(lowered)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(left)
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(index)
        try state.output.appendBorrowed("\n  %v")
        try state.output.appendCopy(rightId)
        try state.output.appendBorrowed(" = extractvalue ")
        try state.output.appendCopy(lowered)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(right)
        try state.output.appendBorrowed(", ")
        try state.output.appendCopy(index)
        try state.output.appendBorrowed("\n  %v")
        try state.output.appendCopy(compareId)
        try state.output.appendBorrowed(" = icmp eq ptr %v")
        try state.output.appendCopy(leftId)
        try state.output.appendBorrowed(", %v")
        try state.output.appendCopy(rightId)
        try state.output.appendBorrowed("\n")
        if protoFieldIndex == 0:
            comparison0Id = compareValueId
        else:
            comparison1Id = compareValueId
        ..
    ..
    combinedId := try strconv.formatUint(state.nextValue)
    defer combinedId.free()
    state.nextValue = state.nextValue + 1
    comparison0Number := try strconv.formatUint(comparison0Id)
    defer comparison0Number.free()
    comparison0 := try strings.concat("%v", comparison0Number)
    defer comparison0.free()
    comparison1Number := try strconv.formatUint(comparison1Id)
    defer comparison1Number.free()
    comparison1 := try strings.concat("%v", comparison1Number)
    defer comparison1.free()
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(combinedId)
    try state.output.appendBorrowed(" = and i1 ")
    try state.output.appendCopy(comparison0)
    try state.output.appendBorrowed(", ")
    try state.output.appendCopy(comparison1)
    try state.output.appendBorrowed("\n")
    if negate:
        negatedId := try strconv.formatUint(state.nextValue)
        defer negatedId.free()
        state.nextValue = state.nextValue + 1
        try state.output.appendBorrowed("  %v")
        try state.output.appendCopy(negatedId)
        try state.output.appendBorrowed(" = xor i1 %v")
        try state.output.appendCopy(combinedId)
        try state.output.appendBorrowed(", true\n")
        ret try strings.concat("%v", negatedId)
    ..
    ret try strings.concat("%v", combinedId)
..

emitBinary(state LoweringState*, result nt.Type*, operation u8, leftExpr nt.Expr*, rightExpr nt.Expr*, protoEquality bool, stringEquality bool, floatingPoint bool, unsignedOperation bool) !$str:
    if operation == tokens.KwType.ANDAND || operation == tokens.KwType.OROR:
        ret try emitLogicalBinary(state, operation, leftExpr, rightExpr)
    ..
    left := try emitExpr(state, leftExpr)
    defer left.free()
    right := try emitExpr(state, rightExpr)
    defer right.free()
    if operation == tokens.KwType.CMP_EQ || operation == tokens.KwType.CMP_NEQ:
        if stringEquality:
            leftDataId := try strconv.formatUint(state.nextValue)
            defer leftDataId.free()
            state.nextValue = state.nextValue + 1
            leftLengthId := try strconv.formatUint(state.nextValue)
            defer leftLengthId.free()
            state.nextValue = state.nextValue + 1
            rightDataId := try strconv.formatUint(state.nextValue)
            defer rightDataId.free()
            state.nextValue = state.nextValue + 1
            rightLengthId := try strconv.formatUint(state.nextValue)
            defer rightLengthId.free()
            state.nextValue = state.nextValue + 1
            bytesId := try strconv.formatUint(state.nextValue)
            defer bytesId.free()
            state.nextValue = state.nextValue + 1
            compareId := try strconv.formatUint(state.nextValue)
            defer compareId.free()
            state.nextValue = state.nextValue + 1
            lengthId := try strconv.formatUint(state.nextValue)
            defer lengthId.free()
            state.nextValue = state.nextValue + 1
            equalId := try strconv.formatUint(state.nextValue)
            defer equalId.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(leftDataId)
            try state.output.appendBorrowed(" = extractvalue %type.str ")
            try state.output.appendCopy(left)
            try state.output.appendBorrowed(", 0\n  %v")
            try state.output.appendCopy(leftLengthId)
            try state.output.appendBorrowed(" = extractvalue %type.str ")
            try state.output.appendCopy(left)
            try state.output.appendBorrowed(", 1\n  %v")
            try state.output.appendCopy(rightDataId)
            try state.output.appendBorrowed(" = extractvalue %type.str ")
            try state.output.appendCopy(right)
            try state.output.appendBorrowed(", 0\n  %v")
            try state.output.appendCopy(rightLengthId)
            try state.output.appendBorrowed(" = extractvalue %type.str ")
            try state.output.appendCopy(right)
            try state.output.appendBorrowed(", 1\n  %v")
            try state.output.appendCopy(bytesId)
            try state.output.appendBorrowed(" = call i32 @memcmp(ptr %v")
            try state.output.appendCopy(leftDataId)
            try state.output.appendBorrowed(", ptr %v")
            try state.output.appendCopy(rightDataId)
            try state.output.appendBorrowed(", i64 %v")
            try state.output.appendCopy(leftLengthId)
            try state.output.appendBorrowed(")\n  %v")
            try state.output.appendCopy(compareId)
            try state.output.appendBorrowed(" = icmp eq i32 %v")
            try state.output.appendCopy(bytesId)
            try state.output.appendBorrowed(", 0\n  %v")
            try state.output.appendCopy(lengthId)
            try state.output.appendBorrowed(" = icmp eq i64 %v")
            try state.output.appendCopy(leftLengthId)
            try state.output.appendBorrowed(", %v")
            try state.output.appendCopy(rightLengthId)
            try state.output.appendBorrowed("\n  %v")
            try state.output.appendCopy(equalId)
            try state.output.appendBorrowed(" = and i1 %v")
            try state.output.appendCopy(compareId)
            try state.output.appendBorrowed(", %v")
            try state.output.appendCopy(lengthId)
            try state.output.appendBorrowed("\n")
            if operation == tokens.KwType.CMP_NEQ:
                id := try strconv.formatUint(state.nextValue)
                defer id.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(id)
                try state.output.appendBorrowed(" = xor i1 %v")
                try state.output.appendCopy(equalId)
                try state.output.appendBorrowed(", true\n")
                ret try strings.concat("%v", id)
            ..
            ret try strings.concat("%v", equalId)
        ..
    ..
    if protoEquality:
        ret try emitProtoEquality(state, try expressionType(leftExpr), left, right, operation == tokens.KwType.CMP_NEQ)
    ..
    resultType := try typeName(result)
    defer resultType.free()
    leftType := try expressionType(leftExpr)
    opcode str
    comparison := operation == tokens.KwType.CMP_EQ || operation == tokens.KwType.CMP_NEQ || operation == tokens.KwType.CMP_LT || operation == tokens.KwType.CMP_LTEQ || operation == tokens.KwType.CMP_GT || operation == tokens.KwType.CMP_GTEQ
    operandNodeType := leftType
    if not comparison:
        operandNodeType = result
    ..
    operandType := try typeName(operandNodeType)
    defer operandType.free()
    leftSourceType := try expressionType(leftExpr)
    rightSourceType := try expressionType(rightExpr)
    leftValue := try coerceIntegerValue(state, left, leftSourceType, operandNodeType)
    defer leftValue.free()
    rightValue := try coerceIntegerValue(state, right, rightSourceType, operandNodeType)
    defer rightValue.free()
    if floatingPoint:
        if operation == tokens.KwType.PLUS: opcode = "fadd"
        elif operation == tokens.KwType.MINUS: opcode = "fsub"
        elif operation == tokens.KwType.ASTERIX: opcode = "fmul"
        elif operation == tokens.KwType.SLASH: opcode = "fdiv"
        elif operation == tokens.KwType.PERCENT: opcode = "frem"
        elif operation == tokens.KwType.CMP_EQ: opcode = "fcmp oeq"
        elif operation == tokens.KwType.CMP_NEQ: opcode = "fcmp one"
        elif operation == tokens.KwType.CMP_LT: opcode = "fcmp olt"
        elif operation == tokens.KwType.CMP_LTEQ: opcode = "fcmp ole"
        elif operation == tokens.KwType.CMP_GT: opcode = "fcmp ogt"
        elif operation == tokens.KwType.CMP_GTEQ: opcode = "fcmp oge"
        else: throw "unsupported floating-point operator in LLVM lowering"
        ..
    elif operation == tokens.KwType.PLUS: opcode = "add"
    elif operation == tokens.KwType.MINUS: opcode = "sub"
    elif operation == tokens.KwType.ASTERIX: opcode = "mul"
    elif operation == tokens.KwType.SLASH:
        if unsignedOperation:
            opcode = "udiv"
        else:
            opcode = "sdiv"
        ..
    elif operation == tokens.KwType.PERCENT:
        if unsignedOperation:
            opcode = "urem"
        else:
            opcode = "srem"
        ..
    elif operation == tokens.KwType.AMPERSAND: opcode = "and"
    elif operation == tokens.KwType.PIPE: opcode = "or"
    elif operation == tokens.KwType.CARET: opcode = "xor"
    elif operation == tokens.KwType.SHIFT_L: opcode = "shl"
    elif operation == tokens.KwType.SHIFT_R:
        if unsignedOperation:
            opcode = "lshr"
        else:
            opcode = "ashr"
        ..
    elif operation == tokens.KwType.CMP_EQ: opcode = "icmp eq"
    elif operation == tokens.KwType.CMP_NEQ: opcode = "icmp ne"
    elif operation == tokens.KwType.CMP_LT:
        if unsignedOperation:
            opcode = "icmp ult"
        else:
            opcode = "icmp slt"
        ..
    elif operation == tokens.KwType.CMP_LTEQ:
        if unsignedOperation:
            opcode = "icmp ule"
        else:
            opcode = "icmp sle"
        ..
    elif operation == tokens.KwType.CMP_GT:
        if unsignedOperation:
            opcode = "icmp ugt"
        else:
            opcode = "icmp sgt"
        ..
    elif operation == tokens.KwType.CMP_GTEQ:
        if unsignedOperation:
            opcode = "icmp uge"
        else:
            opcode = "icmp sge"
        ..
    else:
        throw "unsupported binary operator in LLVM lowering"
    ..
    id := try strconv.formatUint(state.nextValue)
    defer id.free()
    state.nextValue = state.nextValue + 1
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(id)
    try state.output.appendBorrowed(" = ")
    try state.output.appendCopy(opcode)
    try state.output.appendBorrowed(" ")
    if comparison:
        try state.output.appendCopy(operandType)
    else:
        try state.output.appendCopy(resultType)
    ..
    try state.output.appendBorrowed(" ")
    try state.output.appendCopy(leftValue)
    try state.output.appendBorrowed(", ")
    try state.output.appendCopy(rightValue)
    try state.output.appendBorrowed("\n")
    ret try strings.concat("%v", id)
..

integerWidth(type nt.Type*) !u64:
    name := try typeName(type)
    defer name.free()
    ret integerWidthName(name)
..

integerWidthName(name str) u64:
    if strings.compare(name, "i1"): ret 1 ..
    if strings.compare(name, "i8"): ret 8 ..
    if strings.compare(name, "i16"): ret 16 ..
    if strings.compare(name, "i32"): ret 32 ..
    if strings.compare(name, "i64"): ret 64 ..
    if strings.compare(name, "i128"): ret 128 ..
    ret 0
..

coerceIntegerValue(state LoweringState*, value str, source nt.Type*, target nt.Type*) !$str:
    sourceName := try loweredTypeName(state, source)
    defer sourceName.free()
    targetName := try loweredTypeName(state, target)
    defer targetName.free()
    sourceWidth := integerWidthName(sourceName)
    targetWidth := integerWidthName(targetName)
    if sourceWidth == 0 || targetWidth == 0 || sourceWidth == targetWidth:
        ret try strings.copy(value)
    ..
    opcode str
    if sourceWidth > targetWidth:
        opcode = "trunc"
    elif checker.isUnsignedType(source):
        opcode = "zext"
    else:
        opcode = "sext"
    ..
    id := try strconv.formatUint(state.nextValue)
    defer id.free()
    state.nextValue = state.nextValue + 1
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(id)
    try state.output.appendBorrowed(" = ")
    try state.output.appendCopy(opcode)
    try state.output.appendBorrowed(" ")
    try state.output.appendCopy(sourceName)
    try state.output.appendBorrowed(" ")
    try state.output.appendCopy(value)
    try state.output.appendBorrowed(" to ")
    try state.output.appendCopy(targetName)
    try state.output.appendBorrowed("\n")
    ret try strings.concat("%v", id)
..

lowerReturnValue(state LoweringState*, expression nt.Expr*) !$str:
    if expression == none:
        ret try strings.alloc(0)
    ..
    value := try emitExpr(state, expression)
    targetType := state.returnType
    if isThrowingType(state.returnType):
        innerType nt.Type*, innerError error = throwingValueType(state.returnType)
        if innerError.nok():
            value.free()
            throw innerError
        ..
        targetType = innerType
    ..
    sourceType nt.Type*, expressionTypeError error = expressionType(expression)
    if expressionTypeError.nok():
        value.free()
        throw expressionTypeError
    ..
    sourceLlvmType str, sourceTypeError error = typeName(sourceType)
    if sourceTypeError.nok():
        value.free()
        throw sourceTypeError
    ..
    targetLlvmType str, targetTypeError error = typeName(targetType)
    if targetTypeError.nok():
        sourceLlvmType.free()
        value.free()
        throw targetTypeError
    ..
    defer sourceLlvmType.free()
    defer targetLlvmType.free()
    if strings.compare(sourceLlvmType, targetLlvmType):
        ret move value
    ..
    coerced str, conversionError error = coerceIntegerValue(state, value, sourceType, targetType)
    if conversionError.nok():
        value.free()
        throw conversionError
    ..
    value.free()
    ret move coerced
..

emitReturn(state LoweringState*, expression nt.Expr*) !void:
    resultType := try typeName(state.returnType)
    defer resultType.free()
    value := try lowerReturnValue(state, expression)
    defer value.free()
    try emitDefersUntil(state, none, false)
    if isThrowingType(state.returnType):
        if expression == none:
            try state.output.appendBorrowed("  ret ")
            try state.output.appendCopy(resultType)
            try state.output.appendBorrowed(" zeroinitializer\n")
            ret
        ..
        inner := try throwingValueType(state.returnType)
        if try isVoidType(inner):
            try state.output.appendBorrowed("  ret { %type.error } zeroinitializer\n")
        else:
            valueType := try typeName(inner)
            defer valueType.free()
            inserted := try strconv.formatUint(state.nextValue)
            defer inserted.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(inserted)
            try state.output.appendBorrowed(" = insertvalue ")
            try state.output.appendCopy(resultType)
            try state.output.appendBorrowed(" zeroinitializer, ")
            try state.output.appendCopy(valueType)
            try state.output.appendBorrowed(" ")
            try state.output.appendCopy(value)
            try state.output.appendBorrowed(", 1\n  ret ")
            try state.output.appendCopy(resultType)
            try state.output.appendBorrowed(" %v")
            try state.output.appendCopy(inserted)
            try state.output.appendBorrowed("\n")
        ..
    elif strings.compare(resultType, "void"):
        try state.output.appendBorrowed("  ret void\n")
    else:
        try state.output.appendBorrowed("  ret ")
        resultValueType := try typeName(state.returnType)
        defer resultValueType.free()
        try state.output.appendCopy(resultValueType)
        try state.output.appendBorrowed(" ")
        try state.output.appendCopy(value)
        try state.output.appendBorrowed("\n")
    ..
..

emitDeferred(state LoweringState*, statement nt.Stmt*, failing bool) !void:
    node := nt.loadStatementNode(statement)
    match addrof node as deferred:
    case nt.Stmt.Defer:
        if deferred.body != none:
            terminated := try emitStatement(state, deferred.body)
            if terminated:
                throw "control transfer from a deferred body is not supported"
            ..
        elif deferred.expr != none:
            result := try emitExpr(state, deferred.expr)
            result.free()
        ..
    case nt.Stmt.OnError:
        if not failing:
            ret
        ..
        if deferred.body != none:
            terminated := try emitStatement(state, deferred.body)
            if terminated:
                throw "control transfer from an onerror body is not supported"
            ..
        elif deferred.expr != none:
            result := try emitExpr(state, deferred.expr)
            result.free()
        ..
    else:
        throw "defer frame contains a non-defer statement"
    ..
..

emitFrameDefers(state LoweringState*, frame DeferFrame*, failing bool) !void:
    index := frame.activeCount
    loop index > 0:
        index = index - 1
        frame.activeCount = index
        statement := try frame.deferred.get(index)
        node := nt.loadStatementNode(statement)
        match addrof node as candidate:
        case nt.Stmt.Defer:
            try emitDeferred(state, statement, failing)
        case nt.Stmt.OnError:
            try emitDeferred(state, statement, failing)
        else:
            continue
        ..
    ..
    frame.activeCount = 0
..

freeDeferFrame(frame DeferFrame*) void:
    if frame.deferred.data != none:
        ctx.alloc.free(frame.deferred.data)
        frame.deferred.data = none
    ..
..

emitDefersUntil(state LoweringState*, boundary DeferFrame*, failing bool) !void:
    frame := state.deferFrame
    loop frame != boundary:
        if frame == none:
            throw "defer unwind boundary is not an active lexical scope"
        ..
        try emitFrameDefers(state, frame, failing)
        state.deferFrame = frame.parent
        frame = frame.parent
    ..
..

emitBody(state LoweringState*, statements nt.NodeArray[nt.Stmt*]) !bool:
    frame := DeferFrame(parent=state.deferFrame, deferred=nt.emptyStatementArray(), activeCount=0, savedCount=0)
    defer freeDeferFrame(addrof frame)
    for i := 0 to statements.count():
        statement := try statements.get(i)
        node := nt.loadStatementNode(statement)
        match addrof node as candidate:
        case nt.Stmt.Defer:
            try frame.deferred.pushRight(ctx.alloc, statement)
        case nt.Stmt.OnError:
            try frame.deferred.pushRight(ctx.alloc, statement)
        else:
            continue
        ..
    ..
    state.deferFrame = addrof frame
    terminated := false
    for i := 0 to statements.count():
        statement := try statements.get(i)
        node := nt.loadStatementNode(statement)
        match addrof node as candidate:
        case nt.Stmt.Defer:
            frame.activeCount = frame.activeCount + 1
            continue
        case nt.Stmt.OnError:
            frame.activeCount = frame.activeCount + 1
            continue
        else:
            if try emitStatement(state, statement):
                terminated = true
                break
            ..
        ..
    ..
    if not terminated:
        try emitFrameDefers(state, addrof frame, false)
    ..
    state.deferFrame = frame.parent
    ret terminated
..

emitStatement(state LoweringState*, statement nt.Stmt*) !bool:
    match statement as value:
    case nt.Stmt.Body:
        ret try emitBody(state, value.statements)
    case nt.Stmt.Expression:
        expressionNode := nt.loadExpressionNode(value.expr)
        match addrof expressionNode as expressionValue:
        case nt.Expr.Return:
            try emitReturn(state, expressionValue.expr)
            ret true
        case nt.Expr.Throw:
            try emitThrow(state, expressionValue.expr)
            ret true
        case nt.Expr.DirectCall:
            discarded := try emitExpr(state, value.expr)
            discarded.free()
            ret false
        case nt.Expr.VarDef:
            discarded := try emitExpr(state, value.expr)
            discarded.free()
            ret false
        case nt.Expr.VarDefAssign:
            discarded := try emitExpr(state, value.expr)
            discarded.free()
            ret false
        case nt.Expr.Assign:
            discarded := try emitExpr(state, value.expr)
            discarded.free()
            ret false
        case nt.Expr.Binary:
            discarded := try emitExpr(state, value.expr)
            discarded.free()
            ret false
        else:
            discarded := try emitExpr(state, value.expr)
            discarded.free()
            ret false
        ..
    case nt.Stmt.Unsafe:
        if value.body != none:
            ret try emitStatement(state, value.body)
        ..
        if value.expr != none:
            discarded := try emitExpr(state, value.expr)
            discarded.free()
        ..
        ret false
    case nt.Stmt.Bounded:
        ret try emitStatement(state, value.body)
    case nt.Stmt.LLVM:
        try state.output.appendCopy(value.text)
        try state.output.appendBorrowed("\n")
        ret false
    case nt.Stmt.If:
        mergeId := try strconv.formatUint(state.nextBlock)
        defer mergeId.free()
        state.nextBlock = state.nextBlock + 1
        mergeLabel := try strings.concat("if_end_", mergeId)
        defer mergeLabel.free()
        terminated := try emitIfChain(state, value.condition, value.body, value.next, mergeLabel)
        if terminated:
            ret true
        ..
        try state.output.appendCopy(mergeLabel)
        try state.output.appendBorrowed(":\n")
        try setCurrentBlock(state, mergeLabel)
        ret false
    case nt.Stmt.Loop:
        loopId := try strconv.formatUint(state.nextBlock)
        defer loopId.free()
        state.nextBlock = state.nextBlock + 1
        headerLabel := try strings.concat("loop_head_", loopId)
        defer headerLabel.free()
        bodyLabel := try strings.concat("loop_body_", loopId)
        defer bodyLabel.free()
        endLabel := try strings.concat("loop_end_", loopId)
        defer endLabel.free()
        try state.output.appendBorrowed("  br label %")
        try state.output.appendCopy(headerLabel)
        try state.output.appendBorrowed("\n")
        try state.output.appendCopy(headerLabel)
        try state.output.appendBorrowed(":\n")
        try setCurrentBlock(state, headerLabel)
        condition := try emitExpr(state, value.condition)
        defer condition.free()
        try state.output.appendBorrowed("  br i1 ")
        try state.output.appendCopy(condition)
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(bodyLabel)
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(endLabel)
        try state.output.appendBorrowed("\n")
        try state.output.appendCopy(bodyLabel)
        try state.output.appendBorrowed(":\n")
        try setCurrentBlock(state, bodyLabel)
        oldBreak := state.breakTarget
        oldContinue := state.continueTarget
        oldBoundary := state.loopDeferBoundary
        state.breakTarget = endLabel
        state.continueTarget = headerLabel
        state.loopDeferBoundary = state.deferFrame
        bodyTerminated := try emitStatement(state, value.body)
        state.breakTarget = oldBreak
        state.continueTarget = oldContinue
        state.loopDeferBoundary = oldBoundary
        if not bodyTerminated:
            try state.output.appendBorrowed("  br label %")
            try state.output.appendCopy(headerLabel)
            try state.output.appendBorrowed("\n")
        ..
        try state.output.appendCopy(endLabel)
        try state.output.appendBorrowed(":\n")
        try setCurrentBlock(state, endLabel)
        ret false
    case nt.Stmt.ForLoop:
        indexNode := nt.loadExpressionNode(value.index)
        match addrof indexNode as indexValue:
        case nt.Expr.VarDefAssign:
            if indexValue.decl == none:
                throw "for-loop index has no linked declaration"
            ..
            indexType := try typeName(indexValue.type)
            defer indexType.free()
            indexId := try strconv.formatUint(indexValue.decl.id)
            defer indexId.free()
            indexInit := try emitExpr(state, indexValue.assignment)
            defer indexInit.free()
            initType := try expressionType(indexValue.assignment)
            initValue := try coerceIntegerValue(state, indexInit, initType, indexValue.type)
            defer initValue.free()
            try state.output.appendBorrowed("  store ")
            try state.output.appendCopy(indexType)
            try state.output.appendBorrowed(" ")
            try state.output.appendCopy(initValue)
            try state.output.appendBorrowed(", ptr %slot")
            try state.output.appendCopy(indexId)
            try state.output.appendBorrowed("\n")
            loopId := try strconv.formatUint(state.nextBlock)
            defer loopId.free()
            state.nextBlock = state.nextBlock + 1
            headerLabel := try strings.concat("for_head_", loopId)
            defer headerLabel.free()
            bodyLabel := try strings.concat("for_body_", loopId)
            defer bodyLabel.free()
            stepLabel := try strings.concat("for_step_", loopId)
            defer stepLabel.free()
            endLabel := try strings.concat("for_end_", loopId)
            defer endLabel.free()
            try state.output.appendBorrowed("  br label %")
            try state.output.appendCopy(headerLabel)
            try state.output.appendBorrowed("\n")
            try state.output.appendCopy(headerLabel)
            try state.output.appendBorrowed(":\n")
            try setCurrentBlock(state, headerLabel)
            indexTemp := try strconv.formatUint(state.nextValue)
            defer indexTemp.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(indexTemp)
            try state.output.appendBorrowed(" = load ")
            try state.output.appendCopy(indexType)
            try state.output.appendBorrowed(", ptr %slot")
            try state.output.appendCopy(indexId)
            try state.output.appendBorrowed("\n")
            bound := try emitExpr(state, value.bound)
            defer bound.free()
            boundType := try expressionType(value.bound)
            boundTypeName := try typeName(boundType)
            defer boundTypeName.free()
            if strings.compare(indexType, boundTypeName) == false:
                throw "for-loop index and bound lower to different LLVM types"
            ..
            comparison := try strconv.formatUint(state.nextValue)
            defer comparison.free()
            state.nextValue = state.nextValue + 1
            compareOp := "icmp slt"
            if checker.isUnsignedType(indexValue.type):
                compareOp = "icmp ult"
            ..
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(comparison)
            try state.output.appendBorrowed(" = ")
            try state.output.appendCopy(compareOp)
            try state.output.appendBorrowed(" ")
            try state.output.appendCopy(indexType)
            try state.output.appendBorrowed(" %v")
            try state.output.appendCopy(indexTemp)
            try state.output.appendBorrowed(", ")
            try state.output.appendCopy(bound)
            try state.output.appendBorrowed("\n  br i1 %v")
            try state.output.appendCopy(comparison)
            try state.output.appendBorrowed(", label %")
            try state.output.appendCopy(bodyLabel)
            try state.output.appendBorrowed(", label %")
            try state.output.appendCopy(endLabel)
            try state.output.appendBorrowed("\n")
            try state.output.appendCopy(bodyLabel)
            try state.output.appendBorrowed(":\n")
            try setCurrentBlock(state, bodyLabel)
            oldBreak := state.breakTarget
            oldContinue := state.continueTarget
            oldBoundary := state.loopDeferBoundary
            state.breakTarget = endLabel
            state.continueTarget = stepLabel
            state.loopDeferBoundary = state.deferFrame
            bodyTerminated := try emitStatement(state, value.body)
            state.breakTarget = oldBreak
            state.continueTarget = oldContinue
            state.loopDeferBoundary = oldBoundary
            if not bodyTerminated:
                try state.output.appendBorrowed("  br label %")
                try state.output.appendCopy(stepLabel)
                try state.output.appendBorrowed("\n")
            ..
            try state.output.appendCopy(stepLabel)
            try state.output.appendBorrowed(":\n")
            try setCurrentBlock(state, stepLabel)
            updated := try strconv.formatUint(state.nextValue)
            defer updated.free()
            one := "1"
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %v")
            try state.output.appendCopy(updated)
            try state.output.appendBorrowed(" = add ")
            try state.output.appendCopy(indexType)
            try state.output.appendBorrowed(" %v")
            try state.output.appendCopy(indexTemp)
            try state.output.appendBorrowed(", ")
            try state.output.appendCopy(one)
            try state.output.appendBorrowed("\n  store ")
            try state.output.appendCopy(indexType)
            try state.output.appendBorrowed(" %v")
            try state.output.appendCopy(updated)
            try state.output.appendBorrowed(", ptr %slot")
            try state.output.appendCopy(indexId)
            try state.output.appendBorrowed("\n  br label %")
            try state.output.appendCopy(headerLabel)
            try state.output.appendBorrowed("\n")
            try state.output.appendCopy(endLabel)
            try state.output.appendBorrowed(":\n")
            try setCurrentBlock(state, endLabel)
        else:
            throw "for-loop index is not an initialized local"
        ..
        ret false
    case nt.Stmt.Match:
        ret try emitMatch(state, value)
    case nt.Stmt.Break:
        if strings.compare(state.breakTarget, ""):
            throw "break used outside a lowered loop"
        ..
        try emitDefersUntil(state, state.loopDeferBoundary, false)
        try state.output.appendBorrowed("  br label %")
        try state.output.appendCopy(state.breakTarget)
        try state.output.appendBorrowed("\n")
        ret true
    case nt.Stmt.Continue:
        if strings.compare(state.continueTarget, ""):
            throw "continue used outside a lowered loop"
        ..
        try emitDefersUntil(state, state.loopDeferBoundary, false)
        try state.output.appendBorrowed("  br label %")
        try state.output.appendCopy(state.continueTarget)
        try state.output.appendBorrowed("\n")
        ret true
    case nt.Stmt.Elif:
        mergeId := try strconv.formatUint(state.nextBlock)
        defer mergeId.free()
        state.nextBlock = state.nextBlock + 1
        mergeLabel := try strings.concat("if_end_", mergeId)
        defer mergeLabel.free()
        terminated := try emitIfChain(state, value.condition, value.body, value.next, mergeLabel)
        if terminated:
            ret true
        ..
        try state.output.appendCopy(mergeLabel)
        try state.output.appendBorrowed(":\n")
        try setCurrentBlock(state, mergeLabel)
        ret false
    case nt.Stmt.Else:
        ret try emitStatement(state, value.body)
    case nt.Stmt.Defer:
        ret false
    case nt.Stmt.OnError:
        ret false
    else:
        throw "unsupported statement in LLVM lowering"
    ..
..

emitIfChain(state LoweringState*, condition nt.Expr*, body nt.Stmt*, next nt.Stmt*, mergeLabel str) !bool:
    id := try strconv.formatUint(state.nextBlock)
    defer id.free()
    state.nextBlock = state.nextBlock + 1
    thenLabel := try strings.concat("if_then_", id)
    defer thenLabel.free()
    elseLabel := try strings.concat("if_else_", id)
    defer elseLabel.free()
    predicate := try emitExpr(state, condition)
    defer predicate.free()
    predicateType := try expressionType(condition)
    llvmPredicateType := try typeName(predicateType)
    defer llvmPredicateType.free()
    try state.output.appendBorrowed("  br ")
    try state.output.appendCopy(llvmPredicateType)
    try state.output.appendBorrowed(" ")
    try state.output.appendCopy(predicate)
    try state.output.appendBorrowed(", label %")
    try state.output.appendCopy(thenLabel)
    try state.output.appendBorrowed(", label %")
    try state.output.appendCopy(elseLabel)
    try state.output.appendBorrowed("\n")

    try state.output.appendCopy(thenLabel)
    try state.output.appendBorrowed(":\n")
    try setCurrentBlock(state, thenLabel)
    thenTerminated := try emitStatement(state, body)
    if not thenTerminated:
        try state.output.appendBorrowed("  br label %")
        try state.output.appendCopy(mergeLabel)
        try state.output.appendBorrowed("\n")
    ..
    try state.output.appendCopy(elseLabel)
    try state.output.appendBorrowed(":\n")
    try setCurrentBlock(state, elseLabel)
    elseTerminated := false
    if next == none:
        try state.output.appendBorrowed("  br label %")
        try state.output.appendCopy(mergeLabel)
        try state.output.appendBorrowed("\n")
    else:
        nextNode := nt.loadStatementNode(next)
        match addrof nextNode as following:
        case nt.Stmt.Elif:
            elseTerminated = try emitIfChain(state, following.condition, following.body, following.next, mergeLabel)
        case nt.Stmt.Else:
            elseTerminated = try emitStatement(state, following.body)
            if not elseTerminated:
                try state.output.appendBorrowed("  br label %")
                try state.output.appendCopy(mergeLabel)
                try state.output.appendBorrowed("\n")
            ..
        else:
            throw "conditional chain contains an invalid continuation"
        ..
    ..
    ret thenTerminated && elseTerminated
..

emitMatch(state LoweringState*, value nt.Stmt.Match*) !bool:
    matchType := try expressionType(value.expression)
    unionDecl := try structDeclaration(matchType)
    isPointerMatch := value.pointerMode
    unionSymbol := try typeIdentity(unionDecl)
    defer unionSymbol.free()
    unionType := try strings.concat("%", unionSymbol)
    defer unionType.free()
    ownerPointer str
    if value.pointerMode:
        ownerPointer = try emitExpr(state, value.expression)
    else:
        if try isAssignableExpression(value.expression):
            ownerPointer = try emitLValuePointer(state, value.expression)
        else:
            ownerValue := try emitExpr(state, value.expression)
            defer ownerValue.free()
            ownerLlvmType := try typeName(matchType)
            defer ownerLlvmType.free()
            slot := try strconv.formatUint(state.nextValue)
            defer slot.free()
            state.nextValue = state.nextValue + 1
            try state.output.appendBorrowed("  %tmp.slot")
            try state.output.appendCopy(slot)
            try state.output.appendBorrowed(" = alloca ")
            try state.output.appendCopy(ownerLlvmType)
            try state.output.appendBorrowed("\n  store ")
            try state.output.appendCopy(ownerLlvmType)
            try state.output.appendBorrowed(" ")
            try state.output.appendCopy(ownerValue)
            try state.output.appendBorrowed(", ptr %tmp.slot")
            try state.output.appendCopy(slot)
            try state.output.appendBorrowed("\n")
            ownerPointer = try strings.concat("%tmp.slot", slot)
        ..
    ..
    defer ownerPointer.free()
    tagPointerId := try strconv.formatUint(state.nextValue)
    defer tagPointerId.free()
    state.nextValue = state.nextValue + 1
    tagId := try strconv.formatUint(state.nextValue)
    defer tagId.free()
    state.nextValue = state.nextValue + 1
    payloadPointerValue := state.nextValue
    payloadPointerId := try strconv.formatUint(state.nextValue)
    defer payloadPointerId.free()
    state.nextValue = state.nextValue + 1
    matchId := try strconv.formatUint(state.nextBlock)
    defer matchId.free()
    state.nextBlock = state.nextBlock + 1
    mergeLabel := try strings.concat("match_end_", matchId)
    defer mergeLabel.free()
    defaultLabel := try strings.concat("match_default_", matchId)
    defer defaultLabel.free()
    try state.output.appendBorrowed("  %v")
    try state.output.appendCopy(tagPointerId)
    try state.output.appendBorrowed(" = getelementptr ")
    try state.output.appendCopy(unionType)
    try state.output.appendBorrowed(", ptr ")
    try state.output.appendCopy(ownerPointer)
    try state.output.appendBorrowed(", i32 0, i32 0\n  %v")
    try state.output.appendCopy(tagId)
    try state.output.appendBorrowed(" = load i32, ptr %v")
    try state.output.appendCopy(tagPointerId)
    try state.output.appendBorrowed("\n  %v")
    try state.output.appendCopy(payloadPointerId)
    try state.output.appendBorrowed(" = getelementptr ")
    try state.output.appendCopy(unionType)
    try state.output.appendBorrowed(", ptr ")
    try state.output.appendCopy(ownerPointer)
    try state.output.appendBorrowed(", i32 0, i32 2\n  switch i32 %v")
    try state.output.appendCopy(tagId)
    try state.output.appendBorrowed(", label %")
    try state.output.appendCopy(defaultLabel)
    try state.output.appendBorrowed(" [\n")
    for i := 0 to value.cases.count():
        item := try value.cases.get(i)
        if item.decl == none:
            throw "match arm has no checked variant declaration"
        ..
        variant := item.decl
        info := try unionVariantInfo(variant)
        tag := try strconv.formatUint(info.tag)
        defer tag.free()
        armIndex := try strconv.formatUint(i)
        defer armIndex.free()
        casePrefix := try strings.concat("match_case_", matchId)
        defer casePrefix.free()
        caseLabel := try strings.concat(casePrefix, "_")
        defer caseLabel.free()
        fullCaseLabel := try strings.concat(caseLabel, armIndex)
        defer fullCaseLabel.free()
        try state.output.appendBorrowed("    i32 ")
        try state.output.appendCopy(tag)
        try state.output.appendBorrowed(", label %")
        try state.output.appendCopy(fullCaseLabel)
        try state.output.appendBorrowed("\n")
    ..
    try state.output.appendBorrowed("  ]\n")
    allBranchesTerminated := true
    for i := 0 to value.cases.count():
        item := try value.cases.get(i)
        armIndex := try strconv.formatUint(i)
        defer armIndex.free()
        casePrefix := try strings.concat("match_case_", matchId)
        defer casePrefix.free()
        caseLabel := try strings.concat(casePrefix, "_")
        defer caseLabel.free()
        fullCaseLabel := try strings.concat(caseLabel, armIndex)
        defer fullCaseLabel.free()
        try state.output.appendCopy(fullCaseLabel)
        try state.output.appendBorrowed(":\n")
        try setCurrentBlock(state, fullCaseLabel)
        previousBinding := state.matchBindingDecl
        previousPointerId := state.matchBindingPointerId
        previousPointerKind := state.matchBindingPointerKind
        previousIsPointer := state.matchBindingIsPointer
        if value.bindingDecl != none:
            if isPointerMatch:
                bindingId := try strconv.formatUint(value.bindingDecl.id)
                defer bindingId.free()
                try state.output.appendBorrowed("  store ptr %v")
                try state.output.appendCopy(payloadPointerId)
                try state.output.appendBorrowed(", ptr %slot")
                try state.output.appendCopy(bindingId)
                try state.output.appendBorrowed("\n")
            ..
            state.matchBindingDecl = value.bindingDecl
            state.matchBindingPointerId = payloadPointerValue
            state.matchBindingPointerKind = 1
            state.matchBindingIsPointer = isPointerMatch
        ..
        terminated := try emitStatement(state, item.body)
        state.matchBindingDecl = previousBinding
        state.matchBindingPointerId = previousPointerId
        state.matchBindingPointerKind = previousPointerKind
        state.matchBindingIsPointer = previousIsPointer
        if not terminated:
            allBranchesTerminated = false
            try state.output.appendBorrowed("  br label %")
            try state.output.appendCopy(mergeLabel)
            try state.output.appendBorrowed("\n")
        ..
    ..
    try state.output.appendCopy(defaultLabel)
    try state.output.appendBorrowed(":\n")
    try setCurrentBlock(state, defaultLabel)
    if value.elseBody != none:
        previousBinding := state.matchBindingDecl
        previousPointerId := state.matchBindingPointerId
        previousPointerKind := state.matchBindingPointerKind
        previousIsPointer := state.matchBindingIsPointer
        if value.bindingDecl != none:
            bindingId := try strconv.formatUint(value.bindingDecl.id)
            defer bindingId.free()
            if isPointerMatch:
                try state.output.appendBorrowed("  store ptr ")
                try state.output.appendCopy(ownerPointer)
                try state.output.appendBorrowed(", ptr %slot")
                try state.output.appendCopy(bindingId)
                try state.output.appendBorrowed("\n")
            else:
                loadedId := try strconv.formatUint(state.nextValue)
                defer loadedId.free()
                state.nextValue = state.nextValue + 1
                try state.output.appendBorrowed("  %v")
                try state.output.appendCopy(loadedId)
                try state.output.appendBorrowed(" = load ")
                try state.output.appendCopy(unionType)
                try state.output.appendBorrowed(", ptr ")
                try state.output.appendCopy(ownerPointer)
                try state.output.appendBorrowed("\n  store ")
                try state.output.appendCopy(unionType)
                try state.output.appendBorrowed(" %v")
                try state.output.appendCopy(loadedId)
                try state.output.appendBorrowed(", ptr %slot")
                try state.output.appendCopy(bindingId)
                try state.output.appendBorrowed("\n")
            ..
            state.matchBindingDecl = value.bindingDecl
            state.matchBindingPointerId = value.bindingDecl.id
            state.matchBindingPointerKind = 2
            state.matchBindingIsPointer = isPointerMatch
        ..
        terminated := try emitStatement(state, value.elseBody)
        state.matchBindingDecl = previousBinding
        state.matchBindingPointerId = previousPointerId
        state.matchBindingPointerKind = previousPointerKind
        state.matchBindingIsPointer = previousIsPointer
        if not terminated:
            allBranchesTerminated = false
            try state.output.appendBorrowed("  br label %")
            try state.output.appendCopy(mergeLabel)
            try state.output.appendBorrowed("\n")
        ..
    else:
        try state.output.appendBorrowed("  unreachable\n")
    ..
    if allBranchesTerminated:
        ret true
    ..
    try state.output.appendCopy(mergeLabel)
    try state.output.appendBorrowed(":\n")
    try setCurrentBlock(state, mergeLabel)
    ret false
..

appendFunctionSignature(out builder.Builder*, declaration dclr.Decl*, returnType nt.Type*, isDefinition bool) !void:
    resultType := try typeName(returnType)
    defer resultType.free()
    symbol := try declarationLinkName(declaration)
    defer symbol.free()
    if isDefinition:
        try out.appendBorrowed("define ")
    else:
        try out.appendBorrowed("declare ")
    ..
    try out.appendCopy(resultType)
    try out.appendBorrowed(" @")
    try out.appendCopy(symbol)
    try out.appendBorrowed("(")
    noContext := try declarationNoContext(declaration)
    if not noContext:
        try out.appendBorrowed("ptr")
        if isDefinition:
            try out.appendBorrowed(" %ctx.in")
        ..
    ..
    receiver := try methodReceiver(declaration)
    if receiver != none:
        if not noContext:
            try out.appendBorrowed(", ")
        ..
        match receiver.kind as receiverKind:
        case dclr.DeclKind.Argument:
            try appendType(out, receiverKind.type)
        case dclr.DeclKind.Variable:
            try appendType(out, receiverKind.type)
        else:
            throw "method receiver has no value type"
        ..
        if isDefinition:
            try out.appendBorrowed(" %arg")
            receiverId := try strconv.formatUint(receiver.id)
            defer receiverId.free()
            try out.appendCopy(receiverId)
        ..
    ..
    match declaration.kind as kind:
    case dclr.DeclKind.Function:
        for i := 0 to kind.args.count():
            if i != 0 || not noContext || receiver != none:
                try out.appendBorrowed(", ")
            ..
            argument := try kind.args.get(i)
            match argument.kind as argumentKind:
            case dclr.DeclKind.Argument:
                try appendType(out, argumentKind.type)
                if isDefinition:
                    try out.appendBorrowed(" ")
                    try appendArgumentName(out, argument)
                ..
            else:
                throw "function argument has no argument declaration"
            ..
        ..
    else:
        throw "LLVM function signature requires a function declaration"
    ..
    try out.appendBorrowed(")")
    if isDefinition:
        try out.appendBorrowed(" {\nentry:\n")
    else:
        try out.appendBorrowed("\n")
    ..
..

emitFunction(out builder.Builder*, declaration dclr.Decl*, returnType nt.Type*, body nt.Stmt*) !void:
    symbolForTrace := try declarationLinkName(declaration)
    defer symbolForTrace.free()
    try appendFunctionSignature(out, declaration, returnType, true)
    receiver := try methodReceiver(declaration)
    if receiver != none:
        receiverType nt.Type* = none
        match receiver.kind as receiverKind:
        case dclr.DeclKind.Argument:
            receiverType = receiverKind.type
        case dclr.DeclKind.Variable:
            receiverType = receiverKind.type
        else:
            throw "method receiver has no value type"
        ..
        id := try strconv.formatUint(receiver.id)
        defer id.free()
        argumentType := try typeName(receiverType)
        defer argumentType.free()
        try out.appendBorrowed("  %slot")
        try out.appendCopy(id)
        try out.appendBorrowed(" = alloca ")
        try out.appendCopy(argumentType)
        try out.appendBorrowed("\n  store ")
        try out.appendCopy(argumentType)
        try out.appendBorrowed(" %arg")
        try out.appendCopy(id)
        try out.appendBorrowed(", ptr %slot")
        try out.appendCopy(id)
        try out.appendBorrowed("\n")
    ..
    match declaration.kind as functionKind:
    case dclr.DeclKind.Function:
        for i := 0 to functionKind.args.count():
            argument := try functionKind.args.get(i)
            match argument.kind as argumentKind:
            case dclr.DeclKind.Argument:
                id := try strconv.formatUint(argument.id)
                defer id.free()
                argumentType := try typeName(argumentKind.type)
                defer argumentType.free()
                try out.appendBorrowed("  %slot")
                try out.appendCopy(id)
                try out.appendBorrowed(" = alloca ")
                try out.appendCopy(argumentType)
                try out.appendBorrowed("\n  store ")
                try out.appendCopy(argumentType)
                try out.appendBorrowed(" %arg")
                try out.appendCopy(id)
                try out.appendBorrowed(", ptr %slot")
                try out.appendCopy(id)
                try out.appendBorrowed("\n")
            else:
                throw "function argument is not an argument declaration"
            ..
        ..
    else:
        throw "function definition has no function declaration"
    ..
    hasContext := not (try declarationNoContext(declaration))
    localContextId := try appendFunctionContextSlot(out, declaration, hasContext)
    state := LoweringState(output=out, returnType=returnType, nextValue=0, nextBlock=0, breakTarget="", continueTarget="", deferFrame=none, loopDeferBoundary=none, hasContext=hasContext, hasLocalContext=localContextId != 0, localContextId=localContextId, currentBlock=try strings.copy("entry"), matchBindingDecl=none, matchBindingPointerId=0, matchBindingPointerKind=0, matchBindingIsPointer=false, genericTypeArgs=nt.emptyTypeArray(), genericTypeParams=dclr.emptyDeclArray())
    loopSlots := try newLoopSlotList()
    defer loopSlots.free()
    try emitForLoopIndexAllocas(addrof state, body, addrof loopSlots)
    terminated := try emitStatement(addrof state, body)
    if not terminated:
        resultType := try typeName(returnType)
        defer resultType.free()
        if isThrowingType(returnType):
            try out.appendBorrowed("  ret ")
            try out.appendCopy(resultType)
            try out.appendBorrowed(" zeroinitializer\n")
        elif strings.compare(resultType, "void"):
            try out.appendBorrowed("  ret void\n")
        else:
            throw try strings.concat("non-void function body does not end in a lowered return: ", symbolForTrace)
        ..
    ..
    try out.appendBorrowed("}\n")
..

appendSpecializedSignature(out builder.Builder*, specialization nt.Specialization*, symbol str, isDefinition bool) !void:
    functionType := nt.loadTypeNode(specialization.concreteType)
    match addrof functionType as signature:
    case nt.Type.Function:
        resultType := try typeName(signature.returnType)
        defer resultType.free()
        if isDefinition:
            try out.appendBorrowed("define ")
        else:
            try out.appendBorrowed("declare ")
        ..
        try out.appendCopy(resultType)
        try out.appendBorrowed(" @")
        try out.appendCopy(symbol)
        try out.appendBorrowed("(")
        noContext := try declarationNoContext(specialization.template)
        if not noContext:
            try out.appendBorrowed("ptr")
            if isDefinition:
                try out.appendBorrowed(" %ctx.in")
            ..
        ..
        receiver := try methodReceiver(specialization.template)
        if receiver != none:
            if not noContext:
                try out.appendBorrowed(", ")
            ..
            match receiver.kind as receiverKind:
            case dclr.DeclKind.Argument:
                try appendType(out, receiverKind.type)
                if isDefinition:
                    try out.appendBorrowed(" %arg")
                    receiverId := try strconv.formatUint(receiver.id)
                    defer receiverId.free()
                    try out.appendCopy(receiverId)
                ..
            case dclr.DeclKind.Variable:
                try appendType(out, receiverKind.type)
                if isDefinition:
                    try out.appendBorrowed(" %arg")
                    receiverId := try strconv.formatUint(receiver.id)
                    defer receiverId.free()
                    try out.appendCopy(receiverId)
                ..
            else:
                throw "specialized method receiver has no value type"
            ..
        ..
        hasLeadingArgument := not noContext || receiver != none
        for i := 0 to specialization.concreteHeader.fields.count():
            if i != 0 || hasLeadingArgument:
                try out.appendBorrowed(", ")
            ..
            fieldPtr := try specialization.concreteHeader.fields.get(i)
            field := nt.loadExpressionNode(fieldPtr)
            match addrof field as argument:
            case nt.Expr.VarDef:
                try appendType(out, argument.type)
                if isDefinition:
                    if argument.decl == none:
                        throw "specialized argument has no declaration"
                    ..
                    try out.appendBorrowed(" ")
                    try appendArgumentName(out, argument.decl)
                ..
            else:
                throw "specialized function header has a non-argument field"
            ..
        ..
        try out.appendBorrowed(")")
        if isDefinition:
            try out.appendBorrowed(" {\nentry:\n")
        else:
            try out.appendBorrowed("\n")
        ..
    else:
        throw "function specialization has a non-function concrete type"
    ..
..

emitSpecializedFunction(out builder.Builder*, specialization nt.Specialization*) !void:
    if specialization.concreteHeader == none || specialization.concreteBody == none:
        throw "function specialization is missing its checked concrete body"
    ..
    symbol := try specializationSymbol(specialization.template, specialization.typeArgs)
    defer symbol.free()
    try appendSpecializedSignature(out, specialization, symbol, true)
    receiver := try methodReceiver(specialization.template)
    if receiver != none:
        receiverType nt.Type* = none
        match receiver.kind as receiverKind:
        case dclr.DeclKind.Argument:
            receiverType = receiverKind.type
        case dclr.DeclKind.Variable:
            receiverType = receiverKind.type
        else:
            throw "specialized method receiver has no value type"
        ..
        id := try strconv.formatUint(receiver.id)
        defer id.free()
        lowered := try typeName(receiverType)
        defer lowered.free()
        try out.appendBorrowed("  %slot")
        try out.appendCopy(id)
        try out.appendBorrowed(" = alloca ")
        try out.appendCopy(lowered)
        try out.appendBorrowed("\n  store ")
        try out.appendCopy(lowered)
        try out.appendBorrowed(" %arg")
        try out.appendCopy(id)
        try out.appendBorrowed(", ptr %slot")
        try out.appendCopy(id)
        try out.appendBorrowed("\n")
    ..
    for i := 0 to specialization.concreteHeader.fields.count():
        fieldPtr := try specialization.concreteHeader.fields.get(i)
        field := nt.loadExpressionNode(fieldPtr)
        match addrof field as argument:
        case nt.Expr.VarDef:
            id := try strconv.formatUint(argument.decl.id)
            defer id.free()
            lowered := try typeName(argument.type)
            defer lowered.free()
            try out.appendBorrowed("  %slot")
            try out.appendCopy(id)
            try out.appendBorrowed(" = alloca ")
            try out.appendCopy(lowered)
            try out.appendBorrowed("\n  store ")
            try out.appendCopy(lowered)
            try out.appendBorrowed(" %arg")
            try out.appendCopy(id)
            try out.appendBorrowed(", ptr %slot")
            try out.appendCopy(id)
            try out.appendBorrowed("\n")
        else:
            throw "specialized function argument is not a variable"
        ..
    ..
    functionType := nt.loadTypeNode(specialization.concreteType)
    match addrof functionType as signature:
    case nt.Type.Function:
        hasContext := not (try declarationNoContext(specialization.template))
        localContextId := try appendFunctionContextSlot(out, specialization.template, hasContext)
        state := LoweringState(output=out, returnType=signature.returnType, nextValue=0, nextBlock=0, breakTarget="", continueTarget="", deferFrame=none, loopDeferBoundary=none, hasContext=hasContext, hasLocalContext=localContextId != 0, localContextId=localContextId, currentBlock=try strings.copy("entry"), matchBindingDecl=none, matchBindingPointerId=0, matchBindingPointerKind=0, matchBindingIsPointer=false, genericTypeArgs=specialization.typeArgs, genericTypeParams=try specializationParameters(specialization))
        loopSlots := try newLoopSlotList()
        defer loopSlots.free()
        try emitForLoopIndexAllocas(addrof state, specialization.concreteBody, addrof loopSlots)
        terminated := try emitStatement(addrof state, specialization.concreteBody)
        if not terminated:
            if try isVoidType(signature.returnType):
                try out.appendBorrowed("  ret void\n")
            elif isThrowingType(signature.returnType):
                lowered := try typeName(signature.returnType)
                defer lowered.free()
                try out.appendBorrowed("  ret ")
                try out.appendCopy(lowered)
                try out.appendBorrowed(" zeroinitializer\n")
            else:
                throw "specialized non-void function does not return a value"
            ..
        ..
    else:
        throw "specialized function has a non-function type"
    ..
    try out.appendBorrowed("}\n")
..

emitSpecializedStruct(out builder.Builder*, specialization nt.Specialization*) !void:
    if specialization.concreteHeader == none:
        throw "structure specialization is missing its concrete header"
    ..
    symbol := try specializationSymbol(specialization.template, specialization.typeArgs)
    defer symbol.free()
    try out.appendBorrowed("%")
    try out.appendCopy(symbol)
    try out.appendBorrowed(" = type { ")
    for i := 0 to specialization.concreteHeader.fields.count():
        if i != 0:
            try out.appendBorrowed(", ")
        ..
        fieldPtr := try specialization.concreteHeader.fields.get(i)
        field := nt.loadExpressionNode(fieldPtr)
        match addrof field as member:
        case nt.Expr.VarDef:
            try appendType(out, member.type)
        else:
            throw "specialized structure field is not a variable"
        ..
    ..
    try out.appendBorrowed(" }\n")
..

emitStruct(out builder.Builder*, declaration dclr.Decl*) !void:
    if declaration == none:
        throw "structure has no linked declaration"
    ..
    symbol := try typeIdentity(declaration)
    defer symbol.free()
    try out.appendBorrowed("%")
    try out.appendCopy(symbol)
    try out.appendBorrowed(" = type { ")
    match declaration.kind as structure:
    case dclr.DeclKind.Struct:
        for i := 0 to structure.fields.count():
            if i != 0: try out.appendBorrowed(", ") ..
            field := try structure.fields.get(i)
            match field.kind as fieldValue:
            case dclr.DeclKind.Field: try appendType(out, fieldValue.type)
            else: throw "checked structure contains a non-field declaration"
            ..
        ..
    case dclr.DeclKind.UnionVariant:
        for i := 0 to structure.fields.count():
            if i != 0: try out.appendBorrowed(", ") ..
            field := try structure.fields.get(i)
            match field.kind as fieldValue:
            case dclr.DeclKind.Field: try appendType(out, fieldValue.type)
            else: throw "checked union variant contains a non-field declaration"
            ..
        ..
    else:
        throw "LLVM structure definition requires a checked aggregate declaration"
    ..
    try out.appendBorrowed(" }\n")
..

emitProtoDefinition(out builder.Builder*, declaration dclr.Decl*) !void:
    symbol := try typeIdentity(declaration)
    defer symbol.free()
    try out.appendBorrowed("%")
    try out.appendCopy(symbol)
    try out.appendBorrowed(" = type { ptr, ptr }\n")
..

protoVTableSymbol(implementation dclr.Decl*, prototype dclr.Decl*) !$str:
    implementationName := try symbolName(implementation)
    defer implementationName.free()
    prototypeName := try symbolName(prototype)
    defer prototypeName.free()
    prefix := try strings.concat("magma.vtable.", implementationName)
    defer prefix.free()
    joined := try strings.concat(prefix, ".")
    defer joined.free()
    ret try strings.concat(joined, prototypeName)
..

checkedImplementationMethods(implementation dclr.Decl*, prototype dclr.Decl*) !dclr.DeclArray:
    for i := 0 to implementation.protoImplementations.count():
        record := try implementation.protoImplementations.get(i)
        if sameDeclarationIdentity(record.prototype, prototype):
            ret record.methods
        ..
    ..
    throw "checked prototype implementation method mapping is missing"
..

emitImplementationVTable(out builder.Builder*, implementation dclr.Decl*, prototype dclr.Decl*, definition bool) !void:
    prototypeKind := prototype.kind
    match prototypeKind as methods:
    case dclr.DeclKind.Proto:
        count := try strconv.formatUint(methods.methods.count())
        defer count.free()
        table := try protoVTableSymbol(implementation, prototype)
        defer table.free()
        try out.appendBorrowed("@")
        try out.appendCopy(table)
        if definition:
            concreteMethods := try checkedImplementationMethods(implementation, prototype)
            try out.appendBorrowed(" = linkonce_odr constant [")
            try out.appendCopy(count)
            try out.appendBorrowed(" x ptr] [")
            for i := 0 to methods.methods.count():
                required := try methods.methods.get(i)
                requiredKind := required.kind
                match requiredKind as requiredMethod:
                case dclr.DeclKind.Function:
                    concreteMethod := try concreteMethods.get(i)
                    linkName := try declarationLinkName(concreteMethod)
                    defer linkName.free()
                    if i != 0:
                        try out.appendBorrowed(", ")
                    ..
                    try out.appendBorrowed("ptr @")
                    try out.appendCopy(linkName)
                else:
                    throw "protocol vtable method is not a function"
                ..
            ..
            try out.appendBorrowed("]\n")
        else:
            try out.appendBorrowed(" = external constant [")
            try out.appendCopy(count)
            try out.appendBorrowed(" x ptr]\n")
        ..
    else:
        throw "vtable target must be a protocol"
    ..
..

emitVTablesForImplementations(out builder.Builder*, file fctx.FileCtx*, imported bool) !void:
    file.module.declsLock.readLock()
    defer file.module.declsLock.readUnlock()
    for i := 0 to file.module.decls.count():
        implementation := try file.module.decls.get(i)
        implements nt.NodeArray[nt.Type*] = nt.emptyNodeArray[nt.Type*]()
        match implementation.kind as kind:
        case dclr.DeclKind.Struct:
            if kind.typeParams.count() != 0 || (imported && not implementation.isPublic):
                continue
            ..
            implements = kind.implements
        case dclr.DeclKind.Union:
            if imported && not implementation.isPublic:
                continue
            ..
            implements = kind.implements
        else:
            continue
        ..
        for j := 0 to implements.count():
            prototypeType := try implements.get(j)
            prototype := try structDeclaration(prototypeType)
            emitImplementationVTable(out, implementation, prototype, not imported)
        ..
    ..
..

emitUnionDefinition(out builder.Builder*, declaration dclr.Decl*) !void:
    match declaration.kind as unionKind:
    case dclr.DeclKind.Union:
        for i := 0 to unionKind.variants.count():
            try emitStruct(out, try unionKind.variants.get(i))
        ..
    else:
        throw "union layout emission requires a checked union declaration"
    ..
    try emitUnionLayout(out, declaration)
..

typeDefinitionAlreadyEmitted(file fctx.FileCtx*, declaration dclr.Decl*) !bool:
    if strings.compare(file.path, declaration.module.path):
        ret true
    ..
    if not declaration.isPublic:
        ret false
    ..
    for i := 0 to file.imports.count():
        importedPath := try file.imports.get(i)
        if strings.compare(importedPath, declaration.module.path):
            ret true
        ..
    ..
    ret false
..

emitReferencedType(out builder.Builder*, file fctx.FileCtx*, type nt.Type*, seen ls.List[dclr.Decl*]*, seenSpecializations ls.List[str]*) !void:
    if type == none:
        throw "missing checked type in referenced-type traversal"
    ..
    match type as value:
    case nt.Type.Named:
        if value.decl == none:
            # Built-in scalar types have no declaration, but must still be
            # recognized by the ordinary checked-type lowering path.
            lowered := try typeName(type)
            defer lowered.free()
            ret
        ..
        declaration := value.decl
        for i := 0 to seen.count():
            if try seen.get(i) == declaration:
                ret
            ..
        ..
        try seen.pushRight(declaration)
        match declaration.kind as kind:
        case dclr.DeclKind.Alias:
            try emitReferencedType(out, file, kind.target, seen, seenSpecializations)
        case dclr.DeclKind.Enum:
            try emitReferencedType(out, file, kind.backing, seen, seenSpecializations)
        case dclr.DeclKind.Struct:
            if dclr.isImplicitCoreModule(declaration.module):
                ret
            ..
            if kind.typeParams.count() != 0:
                ret
            ..
            for i := 0 to kind.fields.count():
                field := try kind.fields.get(i)
                match field.kind as fieldKind:
                case dclr.DeclKind.Field:
                    try emitReferencedType(out, file, fieldKind.type, seen, seenSpecializations)
                else:
                    throw "checked structure contains a non-field declaration"
                ..
            ..
            if not (try typeDefinitionAlreadyEmitted(file, declaration)):
                try emitStruct(out, declaration)
            ..
        case dclr.DeclKind.Proto:
            if not (try typeDefinitionAlreadyEmitted(file, declaration)):
                try emitProtoDefinition(out, declaration)
            ..
            for i := 0 to kind.methods.count():
                method := try kind.methods.get(i)
                match method.kind as methodKind:
                case dclr.DeclKind.Function:
                    try emitReferencedType(out, file, methodKind.returnType, seen, seenSpecializations)
                    for j := 0 to methodKind.args.count():
                        argument := try methodKind.args.get(j)
                        match argument.kind as argumentKind:
                        case dclr.DeclKind.Argument:
                            try emitReferencedType(out, file, argumentKind.type, seen, seenSpecializations)
                        else:
                            throw "protocol method contains a non-argument"
                        ..
                    ..
                else:
                    throw "protocol contains a non-function method"
                ..
            ..
        case dclr.DeclKind.Union:
            for variantIndex := 0 to kind.variants.count():
                variant := try kind.variants.get(variantIndex)
                match variant.kind as variantKind:
                case dclr.DeclKind.UnionVariant:
                    for fieldPosition := 0 to variantKind.fields.count():
                        field := try variantKind.fields.get(fieldPosition)
                        match field.kind as fieldKind:
                        case dclr.DeclKind.Field:
                            try emitReferencedType(out, file, fieldKind.type, seen, seenSpecializations)
                        else:
                            throw "checked union variant contains a non-field declaration"
                        ..
                    ..
                else:
                    throw "checked union contains a non-variant declaration"
                ..
            ..
            if not (try typeDefinitionAlreadyEmitted(file, declaration)):
                try emitUnionDefinition(out, declaration)
            ..
        case dclr.DeclKind.UnionVariant:
            try emitReferencedType(out, file, kind.unionType, seen, seenSpecializations)
        else:
            ret
        ..
    case nt.Type.Pointer:
        try emitReferencedType(out, file, value.toType, seen, seenSpecializations)
    case nt.Type.Slice:
        try emitReferencedType(out, file, value.ofType, seen, seenSpecializations)
    case nt.Type.Owned:
        try emitReferencedType(out, file, value.ofType, seen, seenSpecializations)
    case nt.Type.Throwing:
        try emitReferencedType(out, file, value.ofType, seen, seenSpecializations)
    case nt.Type.Function:
        try emitReferencedType(out, file, value.returnType, seen, seenSpecializations)
        for i := 0 to value.args.count():
            try emitReferencedType(out, file, value.args.get(i), seen, seenSpecializations)
        ..
    case nt.Type.Templated:
        template := try structDeclaration(value.owner)
        for i := 0 to value.args.count():
            argumentName := try typeName(try value.args.get(i))
            defer argumentName.free()
        ..
        targetSymbol := try specializationSymbol(template, value.args)
        defer targetSymbol.free()
        alreadySeen := false
        for i := 0 to seenSpecializations.count():
            if strings.compare(try seenSpecializations.get(i), targetSymbol):
                alreadySeen = true
                break
            ..
        ..
        if alreadySeen:
            ret
        ..
        try seenSpecializations.pushRight(try strings.copy(targetSymbol))
        provider := try gl.files.get(template.module.path)
        found := false
        for i := 0 to provider.specializations.count():
            specialization := try provider.specializations.get(i)
            if specialization.isFunction || specialization.template != template:
                continue
            ..
            candidateSymbol := try specializationSymbol(template, specialization.typeArgs)
            defer candidateSymbol.free()
            if not strings.compare(candidateSymbol, targetSymbol):
                continue
            ..
            if strings.compare(template.module.path, file.path) == false:
                try emitSpecializedStruct(out, specialization)
            ..
            for specializedFieldIndex := 0 to specialization.concreteHeader.fields.count():
                fieldNode := nt.loadExpressionNode(try specialization.concreteHeader.fields.get(specializedFieldIndex))
                match addrof fieldNode as field:
                case nt.Expr.VarDef:
                    try emitReferencedType(out, file, field.type, seen, seenSpecializations)
                else:
                    throw "specialized structure contains a non-field"
                ..
            ..
            found = true
            break
        ..
        if not found:
            message := try strings.concat("referenced generic structure has no checked specialization: ", targetSymbol)
            throw move message
        ..
    else:
        ret
    ..
..

headerIsTemplated(header nt.Header*) bool:
    match header.kind as kind:
    case nt.HeaderKind.Templated:
        ret true
    else:
        ret false
    ..
..

emitReferencedTypesFromModule(out builder.Builder*, requestingFile fctx.FileCtx*, sourceFile fctx.FileCtx*, publicOnly bool, seen ls.List[dclr.Decl*]*, seenSpecializations ls.List[str]*) !void:
    for i := 0 to sourceFile.astRoot.statements.count():
        statement := nt.loadGlobalStatementNode(try sourceFile.astRoot.statements.get(i))
        declaration dclr.Decl* = none
        isPublic := true
        match addrof statement as value:
        case nt.GlobalStmt.Struct:
            declaration = value.header.decl
            isPublic = value.isPublic
        case nt.GlobalStmt.Proto:
            declaration = try sourceFile.module.getDecl(value.id)
            isPublic = value.isPublic
        case nt.GlobalStmt.Union:
            declaration = try sourceFile.module.getDecl(value.id)
            isPublic = value.isPublic
        case nt.GlobalStmt.Function:
            if headerIsTemplated(value.header):
                continue
            ..
            if not publicOnly || value.isPublic:
                try emitReferencedType(out, requestingFile, value.retType, seen, seenSpecializations)
                for j := 0 to value.header.fields.count():
                    fieldNode := nt.loadExpressionNode(try value.header.fields.get(j))
                    match addrof fieldNode as argument:
                    case nt.Expr.VarDef:
                        try emitReferencedType(out, requestingFile, argument.type, seen, seenSpecializations)
                    else:
                        throw "function header contains a non-argument"
                    ..
                ..
            ..
            continue
        case nt.GlobalStmt.ExternalFunction:
            if not publicOnly || value.isPublic:
                try emitReferencedType(out, requestingFile, value.retType, seen, seenSpecializations)
                for j := 0 to value.header.fields.count():
                    fieldNode := nt.loadExpressionNode(try value.header.fields.get(j))
                    match addrof fieldNode as argument:
                    case nt.Expr.VarDef:
                        try emitReferencedType(out, requestingFile, argument.type, seen, seenSpecializations)
                    else:
                        throw "external function header contains a non-argument"
                    ..
                ..
            ..
            continue
        case nt.GlobalStmt.Method:
            method := nt.loadGlobalStatementNode(value.methodBody)
            match addrof method as methodValue:
            case nt.GlobalStmt.Function:
                if try methodHasGenericOwner(methodValue.header.decl):
                    continue
                ..
                if headerIsTemplated(methodValue.header):
                    continue
                ..
                try emitReferencedType(out, requestingFile, methodValue.retType, seen, seenSpecializations)
                for j := 0 to methodValue.header.fields.count():
                    fieldNode := nt.loadExpressionNode(try methodValue.header.fields.get(j))
                    match addrof fieldNode as argument:
                    case nt.Expr.VarDef:
                        try emitReferencedType(out, requestingFile, argument.type, seen, seenSpecializations)
                    else:
                        throw "method header contains a non-argument"
                    ..
                ..
            else:
                throw "method body is not a function"
            ..
            continue
        case nt.GlobalStmt.Variable:
            if not publicOnly || value.isPublic:
                try emitReferencedType(out, requestingFile, value.type, seen, seenSpecializations)
            ..
            continue
        else:
            continue
        ..
        if declaration == none || (publicOnly && not isPublic):
            continue
        ..
        try emitReferencedType(out, requestingFile, declaration.declType, seen, seenSpecializations)
    ..
..

emitGlobal(out builder.Builder*, declaration dclr.Decl*, variableType nt.Type*, initializerExpr nt.Expr*, isGlobal bool, isConst bool) !void:
    # Every module-level variable has storage. The source modifier controls
    # mutability/visibility semantics, not whether a declaration has an LLVM
    # address.
    isGlobal = isGlobal
    symbol := try symbolName(declaration)
    defer symbol.free()
    if variableType == none:
        match declaration.kind as declarationKind:
        case dclr.DeclKind.Variable:
            variableType = declarationKind.type
        else:
            throw "global declaration has no checked type"
        ..
    ..
    loweredType := try typeName(variableType)
    defer loweredType.free()
    try out.appendBorrowed("@")
    try out.appendCopy(symbol)
    if isConst:
        try out.appendBorrowed(" = constant ")
    else:
        try out.appendBorrowed(" = global ")
    ..
    try out.appendCopy(loweredType)
    try out.appendBorrowed(" ")
    if initializerExpr == none:
        try out.appendBorrowed("zeroinitializer")
    else:
        initializer := nt.loadExpressionNode(initializerExpr)
        match addrof initializer as initialValue:
        case nt.Expr.Named:
            match initialValue.decl.kind as declarationKind:
            case dclr.DeclKind.Variable:
                if not declarationKind.isConst || declarationKind.initializer == none:
                    throw "global name initializer is not a constant variable"
                ..
                constant := try emitConstantExpression(declarationKind.initializer)
                defer constant.free()
                try out.appendCopy(constant)
            case dclr.DeclKind.EnumVariant:
                value := try enumVariantValue(initialValue.decl)
                defer value.free()
                try out.appendCopy(value)
            else:
                throw "global name initializer is not an enum constant"
            ..
        case nt.Expr.Literal:
            match initialValue.literal as literal:
            case nt.Literal.Number:
                try out.appendCopy(literal.value)
            case nt.Literal.HexNumber:
                try out.appendCopy(literal.value)
            case nt.Literal.Boolean:
                if literal.value:
                    try out.appendBorrowed("1")
                else:
                    try out.appendBorrowed("0")
                ..
            case nt.Literal.String:
                constant := try stringConstantValue(literal.value)
                defer constant.free()
                try out.appendCopy(constant)
            case nt.Literal.Char8:
                if literal.value.countBytes() != 1:
                    throw "invalid 8-bit global character literal"
                ..
                character := try strconv.formatUint(cast.u8to64(strings.byteAt(literal.value, 0)))
                defer character.free()
                try out.appendCopy(character)
            case nt.Literal.Char32:
                input u8[] = slices.fromPtr(strings.toPtr(literal.value), literal.value.countBytes())
                codepoint := try utf8.decode(input)
                character := try strconv.formatUint(cast.u32to64(codepoint.value))
                defer character.free()
                try out.appendCopy(character)
            case nt.Literal.None:
                try out.appendBorrowed("null")
            else:
                throw "global literal initializer is not supported by LLVM lowering"
            ..
        case nt.Expr.Sizeof:
            constant := try emitConstantExpression(initializerExpr)
            defer constant.free()
            try out.appendCopy(constant)
        case nt.Expr.CompilerKnown:
            constant := try emitConstantExpression(initializerExpr)
            defer constant.free()
            try out.appendCopy(constant)
        case nt.Expr.Array:
            if initialValue.length == none:
                throw "global array initializer must have a fixed length"
            ..
            length := try emitConstantExpression(initialValue.length)
            defer length.free()
            elementType := try typeName(initialValue.type)
            defer elementType.free()
            backingSymbol := try strings.concat(symbol, ".storage")
            defer backingSymbol.free()
            try out.appendBorrowed("{ ptr getelementptr inbounds ([")
            try out.appendCopy(length)
            try out.appendBorrowed(" x ")
            try out.appendCopy(elementType)
            try out.appendBorrowed("], ptr @")
            try out.appendCopy(backingSymbol)
            try out.appendBorrowed(", i64 0, i64 0), i64 ")
            try out.appendCopy(length)
            try out.appendBorrowed(" }")
            try out.appendBorrowed("\n@")
            try out.appendCopy(backingSymbol)
            try out.appendBorrowed(" = private global [")
            try out.appendCopy(length)
            try out.appendBorrowed(" x ")
            try out.appendCopy(elementType)
            try out.appendBorrowed("] zeroinitializer")
        case nt.Expr.DirectCall:
            if initialValue.callKind != nt.CallKind.StructConstructor:
                throw "global direct initializer is not a checked struct constructor"
            ..
            try emitGlobalStructValue(out, initialValue.decl, initialValue.args)
        case nt.Expr.IndirectCall:
            if initialValue.callKind == nt.CallKind.ArrayConstructor:
                ownerNode := nt.loadExpressionNode(initialValue.owner)
                match addrof ownerNode as array:
                case nt.Expr.Array:
                    try emitGlobalArrayValue(out, symbol, array, initialValue.args)
                else:
                    throw "checked array constructor has no array expression"
                ..
            elif initialValue.callKind == nt.CallKind.StructConstructor && initialValue.target != none:
                try emitGlobalStructValue(out, initialValue.target, initialValue.args)
            else:
                throw "global initializer has no checked constructor classification"
            ..
        case nt.Expr.TemplatedIndirectCall:
            if initialValue.callKind != nt.CallKind.StructConstructor || initialValue.target == none:
                throw "global templated initializer has no checked struct constructor"
            ..
            try emitGlobalStructValue(out, initialValue.target, initialValue.args)
        else:
            throw "global initializer must be a supported LLVM constant"
        ..
    ..
    try out.appendBorrowed("\n")
..

appendExternalGlobal(out builder.Builder*, declaration dclr.Decl*, variableType nt.Type*, isConst bool) !void:
    symbol := try symbolName(declaration)
    defer symbol.free()
    loweredType := try typeName(variableType)
    defer loweredType.free()
    try out.appendBorrowed("@")
    try out.appendCopy(symbol)
    if isConst:
        try out.appendBorrowed(" = external constant ")
    else:
        try out.appendBorrowed(" = external global ")
    ..
    try out.appendCopy(loweredType)
    try out.appendBorrowed("\n")
..

collectImportPaths(file fctx.FileCtx*, paths ls.List[str]*) !void:
    for importIndex := 0 to file.imports.count():
        importPath := try file.imports.get(importIndex)
        seen := false
        for pathIndex := 0 to paths.count():
            if strings.compare(try paths.get(pathIndex), importPath):
                seen = true
                break
            ..
        ..
        if seen:
            continue
        ..
        try paths.pushRight(try strings.copy(importPath))
        dependency := try gl.files.get(importPath)
        try collectImportPaths(dependency, paths)
    ..
..

appendImportedDeclarations(out builder.Builder*, file fctx.FileCtx*) !void:
    # A generic specialization can expose concrete argument types owned by a
    # transitive import. Emit those layouts before signatures that mention
    # them; direct imports are emitted by the ordinary declaration pass below.
    seenTypes := try ls.new[dclr.Decl*](ctx.alloc, none)
    defer seenTypes.free()
    seenSpecializations := try ls.new[str](ctx.alloc, none)
    defer seenSpecializations.free()
    importPaths := try ls.new[str](ctx.alloc, none)
    defer importPaths.free()
    try importPaths.pushRight(try strings.copy(file.path))
    try collectImportPaths(file, addrof importPaths)
    try emitReferencedTypesFromModule(out, file, file, false, addrof seenTypes, addrof seenSpecializations)
    # Emit every direct import's named layouts before any imported signature.
    # Signatures can pass structs from a different direct import by value.
    for directImportIndex := 0 to file.imports.count():
        directImportPath := try file.imports.get(directImportIndex)
        directDependency := try gl.files.get(directImportPath)
        for statementIndex := 0 to directDependency.astRoot.statements.count():
            statement := nt.loadGlobalStatementNode(try directDependency.astRoot.statements.get(statementIndex))
            match addrof statement as importedType:
            case nt.GlobalStmt.Struct:
                if importedType.isPublic:
                    match importedType.header.kind as headerKind:
                    case nt.HeaderKind.Plain:
                        try emitStruct(out, importedType.header.decl)
                    case nt.HeaderKind.Templated:
                        continue
                    ..
                ..
            case nt.GlobalStmt.Proto:
                if importedType.isPublic:
                    declaration := try directDependency.module.getDecl(importedType.id)
                    try emitProtoDefinition(out, declaration)
                ..
            case nt.GlobalStmt.Union:
                if importedType.isPublic:
                    declaration := try directDependency.module.getDecl(importedType.id)
                    try emitUnionDefinition(out, declaration)
                ..
            else:
                continue
            ..
        ..
    ..
    # Resolve all transitive and generic layouts before emitting any imported
    # specialization signature that may pass those layouts by value.
    for importIndex := 0 to importPaths.count():
        importPath := try importPaths.get(importIndex)
        dependency := try gl.files.get(importPath)
        if strings.compare(dependency.path, file.path):
            try emitReferencedTypesFromModule(out, file, dependency, true, addrof seenTypes, addrof seenSpecializations)
            for specializationIndex := 0 to dependency.specializations.count():
                specialization := try dependency.specializations.get(specializationIndex)
                if not specialization.template.isPublic:
                    continue
                ..
                for typeIndex := 0 to specialization.typeArgs.count():
                    try emitReferencedType(out, file, specialization.typeArgs.get(typeIndex), addrof seenTypes, addrof seenSpecializations)
                ..
                try emitReferencedType(out, file, specialization.concreteType, addrof seenTypes, addrof seenSpecializations)
            ..
        ..
    ..
    for specializationIndex := 0 to file.specializations.count():
        specialization := try file.specializations.get(specializationIndex)
        for typeIndex := 0 to specialization.typeArgs.count():
            try emitReferencedType(out, file, specialization.typeArgs.get(typeIndex), addrof seenTypes, addrof seenSpecializations)
        ..
        try emitReferencedType(out, file, specialization.concreteType, addrof seenTypes, addrof seenSpecializations)
        # Specializations are owned and emitted by the module that defines
        # their template. A use in this module therefore needs a declaration
        # even when the generic template itself is not an imported public
        # function (methods are public by default).
        if specialization.isFunction && specialization.template.module != none && not strings.compare(specialization.template.module.path, file.path):
            symbol := try specializationSymbol(specialization.template, specialization.typeArgs)
            defer symbol.free()
            try appendSpecializedSignature(out, specialization, symbol, false)
        ..
    ..
    for importIndex := 0 to importPaths.count():
        importPath := try importPaths.get(importIndex)
        directImport := false
        for directIndex := 0 to file.imports.count():
            if strings.compare(try file.imports.get(directIndex), importPath):
                directImport = true
                break
            ..
        ..
        if directImport:
            continue
        ..
        dependency := try gl.files.get(importPath)
        if strings.compare(dependency.path, file.path):
            continue
        ..
        # Emit public layouts before signatures from transitive imports. A
        # function prototype may pass a struct by value, which LLVM cannot
        # validate while that named type is still opaque.
        try emitReferencedTypesFromModule(out, file, dependency, true, addrof seenTypes, addrof seenSpecializations)
        for statementIndex := 0 to dependency.astRoot.statements.count():
            statement := nt.loadGlobalStatementNode(try dependency.astRoot.statements.get(statementIndex))
            match addrof statement as dependencyStatement:
            case nt.GlobalStmt.Proto:
                for methodIndex := 0 to dependencyStatement.methods.count():
                    method := try dependencyStatement.methods.get(methodIndex)
                    try appendFunctionSignature(out, method.decl, method.returnType, false)
                ..
            case nt.GlobalStmt.Method:
                method := nt.loadGlobalStatementNode(dependencyStatement.methodBody)
                match addrof method as methodValue:
                case nt.GlobalStmt.Function:
                    if try methodHasGenericOwner(methodValue.header.decl):
                        continue
                    ..
                    match methodValue.header.kind as methodHeaderKind:
                    case nt.HeaderKind.Plain:
                        try appendFunctionSignature(out, methodValue.header.decl, methodValue.retType, false)
                    case nt.HeaderKind.Templated:
                        continue
                    ..
                else:
                    continue
                ..
            else:
                continue
            ..
        ..
        for specializationIndex := 0 to dependency.specializations.count():
            specialization := try dependency.specializations.get(specializationIndex)
            if specialization.isFunction && specialization.template.module != none && not strings.compare(specialization.template.module.path, file.path):
                for typeIndex := 0 to specialization.typeArgs.count():
                    try emitReferencedType(out, file, specialization.typeArgs.get(typeIndex), addrof seenTypes, addrof seenSpecializations)
                ..
                try emitReferencedType(out, file, specialization.concreteType, addrof seenTypes, addrof seenSpecializations)
                symbol := try specializationSymbol(specialization.template, specialization.typeArgs)
                defer symbol.free()
                try appendSpecializedSignature(out, specialization, symbol, false)
            ..
        ..
    ..
    for importIndex := 0 to file.imports.count():
        importPath := try file.imports.get(importIndex)
        dependency := try gl.files.get(importPath)
        try emitReferencedTypesFromModule(out, file, dependency, true, addrof seenTypes, addrof seenSpecializations)
        for specializationIndex := 0 to dependency.specializations.count():
            specialization := try dependency.specializations.get(specializationIndex)
            if specialization.template.isPublic:
                for typeIndex := 0 to specialization.typeArgs.count():
                    try emitReferencedType(out, file, specialization.typeArgs.get(typeIndex), addrof seenTypes, addrof seenSpecializations)
                ..
                try emitReferencedType(out, file, specialization.concreteType, addrof seenTypes, addrof seenSpecializations)
            ..
        ..
        if strings.compare(dependency.path, file.path):
            continue
        ..
        for statementIndex := 0 to dependency.astRoot.statements.count():
            statementPtr := try dependency.astRoot.statements.get(statementIndex)
            statement := nt.loadGlobalStatementNode(statementPtr)
            match addrof statement as dependencyType:
            case nt.GlobalStmt.Struct:
                continue
            case nt.GlobalStmt.Proto:
                if dependencyType.isPublic:
                    for methodIndex := 0 to dependencyType.methods.count():
                        method := try dependencyType.methods.get(methodIndex)
                        try appendFunctionSignature(out, method.decl, method.returnType, false)
                    ..
                ..
            case nt.GlobalStmt.Union:
                continue
            else:
                continue
            ..
        ..
        try emitVTablesForImplementations(out, dependency, true)
        for specializationIndex := 0 to dependency.specializations.count():
            specialization := try dependency.specializations.get(specializationIndex)
            if specialization.isFunction == false && specialization.template.isPublic:
                symbol := try specializationSymbol(specialization.template, specialization.typeArgs)
                defer symbol.free()
                alreadyEmitted := false
                for seenIndex := 0 to seenSpecializations.count():
                    if strings.compare(try seenSpecializations.get(seenIndex), symbol):
                        alreadyEmitted = true
                        break
                    ..
                ..
                if not alreadyEmitted:
                    try emitSpecializedStruct(out, specialization)
                    try seenSpecializations.pushRight(try strings.copy(symbol))
                ..
            ..
        ..
        for statementIndex := 0 to dependency.astRoot.statements.count():
            statementPtr := try dependency.astRoot.statements.get(statementIndex)
            statement := nt.loadGlobalStatementNode(statementPtr)
            match addrof statement as dependencyStatement:
            case nt.GlobalStmt.Function:
                if dependencyStatement.isPublic:
                    match dependencyStatement.header.kind as dependencyHeaderKind:
                    case nt.HeaderKind.Plain:
                        try appendFunctionSignature(out, dependencyStatement.header.decl, dependencyStatement.retType, false)
                    case nt.HeaderKind.Templated:
                        continue
                    ..
                ..
            case nt.GlobalStmt.ExternalFunction:
                if dependencyStatement.isPublic:
                    try appendFunctionSignature(out, dependencyStatement.header.decl, dependencyStatement.retType, false)
                ..
            case nt.GlobalStmt.Method:
                method := nt.loadGlobalStatementNode(dependencyStatement.methodBody)
                match addrof method as methodValue:
                case nt.GlobalStmt.Function:
                    if try methodHasGenericOwner(methodValue.header.decl):
                        continue
                    ..
                    match methodValue.header.kind as methodHeaderKind:
                    case nt.HeaderKind.Plain:
                        try appendFunctionSignature(out, methodValue.header.decl, methodValue.retType, false)
                    case nt.HeaderKind.Templated:
                        continue
                    ..
                else:
                    continue
                ..
            case nt.GlobalStmt.Variable:
                if dependencyStatement.isPublic:
                    declaration := try dependency.module.getDecl(dependencyStatement.id)
                    try appendExternalGlobal(out, declaration, dependencyStatement.type, dependencyStatement.isConst)
                ..
            else:
                continue
            ..
        ..
        for specializationIndex := 0 to dependency.specializations.count():
            specialization := try dependency.specializations.get(specializationIndex)
            if specialization.isFunction:
                symbol := try specializationSymbol(specialization.template, specialization.typeArgs)
                defer symbol.free()
                try appendSpecializedSignature(out, specialization, symbol, false)
            ..
        ..
    ..
..

pub emitModule(file fctx.FileCtx*) !$str:
    output := try builder.new()
    defer output.free()
    try output.appendBorrowed("; Magma module\n")
    try output.appendBorrowed("%type.error = type { ptr, i32, i16, i16 }\n")
    try output.appendBorrowed("%type.str = type { ptr, i64, ptr, ptr }\n")
    try output.appendBorrowed("%type.slice = type { ptr, i64 }\n")
    try output.appendBorrowed("declare i32 @memcmp(ptr, ptr, i64)\n")
    try output.appendBorrowed("@magma.context.root = external thread_local global ptr\n")
    try output.appendBorrowed("declare void @llvm.assume(i1 noundef)\n")
    try output.appendBorrowed("declare void @llvm.trap()\n")
    try output.appendBorrowed("declare i16 @llvm.bswap.i16(i16)\n")
    try output.appendBorrowed("declare i32 @llvm.bswap.i32(i32)\n")
    try output.appendBorrowed("declare i64 @llvm.bswap.i64(i64)\n")
    try output.appendBorrowed("declare i8 @llvm.bitreverse.i8(i8)\n")
    try output.appendBorrowed("declare i16 @llvm.bitreverse.i16(i16)\n")
    try output.appendBorrowed("declare i32 @llvm.bitreverse.i32(i32)\n")
    try output.appendBorrowed("declare i64 @llvm.bitreverse.i64(i64)\n")
    try output.appendBorrowed("declare i8 @llvm.ctpop.i8(i8)\n")
    try output.appendBorrowed("declare i16 @llvm.ctpop.i16(i16)\n")
    try output.appendBorrowed("declare i32 @llvm.ctpop.i32(i32)\n")
    try output.appendBorrowed("declare i64 @llvm.ctpop.i64(i64)\n")
    try output.appendBorrowed("declare i32 @llvm.ctlz.i32(i32, i1 immarg)\n")
    try output.appendBorrowed("declare i64 @llvm.ctlz.i64(i64, i1 immarg)\n")
    try output.appendBorrowed("declare i32 @llvm.cttz.i32(i32, i1 immarg)\n")
    try output.appendBorrowed("declare i64 @llvm.cttz.i64(i64, i1 immarg)\n")
    try emitStringGlobals(addrof output, file)
    # Emit named layouts first; LLVM permits forward references, but this
    # ordering also makes the resulting text easier to inspect.
    for i := 0 to file.astRoot.statements.count():
        globalStatement := try file.astRoot.statements.get(i)
        statement := nt.loadGlobalStatementNode(globalStatement)
        match addrof statement as globalValue:
        case nt.GlobalStmt.Struct:
            match globalValue.header.kind as headerKind:
            case nt.HeaderKind.Plain:
                try emitStruct(addrof output, globalValue.header.decl)
            case nt.HeaderKind.Templated:
                continue
            ..
        case nt.GlobalStmt.Proto:
            declaration := try file.module.getDecl(globalValue.id)
            try emitProtoDefinition(addrof output, declaration)
        case nt.GlobalStmt.Union:
            declaration := try file.module.getDecl(globalValue.id)
            try emitUnionDefinition(addrof output, declaration)
        else:
            continue
        ..
    ..
    try emitVTablesForImplementations(addrof output, file, false)
    for i := 0 to file.specializations.count():
        specialization := try file.specializations.get(i)
        if not specialization.isFunction:
            try emitSpecializedStruct(addrof output, specialization)
        ..
    ..
    try appendImportedDeclarations(addrof output, file)
    for i := 0 to file.astRoot.statements.count():
        globalStatement := try file.astRoot.statements.get(i)
        statement := nt.loadGlobalStatementNode(globalStatement)
        match addrof statement as globalValue:
        case nt.GlobalStmt.ExternalFunction:
            try appendFunctionSignature(addrof output, globalValue.header.decl, globalValue.retType, false)
        case nt.GlobalStmt.Function:
            # Templated declarations are emitted from their checked concrete
            # specialization records, not from the open template body.
            match globalValue.header.kind as headerKind:
            case nt.HeaderKind.Templated:
                continue
            case nt.HeaderKind.Plain:
                try emitFunction(addrof output, globalValue.header.decl, globalValue.retType, globalValue.body)
            ..
        case nt.GlobalStmt.Method:
            method := nt.loadGlobalStatementNode(globalValue.methodBody)
            match addrof method as methodValue:
            case nt.GlobalStmt.Function:
                    if try methodHasGenericOwner(methodValue.header.decl):
                        continue
                    ..
                match methodValue.header.kind as methodHeaderKind:
                case nt.HeaderKind.Templated:
                    continue
                case nt.HeaderKind.Plain:
                    try emitFunction(addrof output, methodValue.header.decl, methodValue.retType, methodValue.body)
                ..
            else:
                throw "method body is not a function"
            ..
        case nt.GlobalStmt.LLVM:
            try output.appendCopy(globalValue.text)
            try output.appendBorrowed("\n")
        case nt.GlobalStmt.Variable:
            declaration := try file.module.getDecl(globalValue.id)
            try emitGlobal(addrof output, declaration, globalValue.type, globalValue.initializer, globalValue.isGlobal, globalValue.isConst)
        else:
            continue
        ..
    ..
    for i := 0 to file.specializations.count():
        specialization := try file.specializations.get(i)
        if specialization.isFunction:
            try emitSpecializedFunction(addrof output, specialization)
        ..
    ..
    ret try output.build()
..
