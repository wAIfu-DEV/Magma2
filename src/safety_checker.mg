mod safety_checker
# Path-sensitive ownership checking over the linked, typed AST. The first
# traversal records the destructor-bearing types; the second analyzes checked
# function bodies. No semantic name resolution is repeated here.

use "std:errors" errs
use "std:list" ls

use "shared/filectx" fctx
use "shared/node_types" nt
use "shared/global" gl
use "shared/comperr" comperr
use "shared/origin" org
use "shared/token_types" tkt
use "decl_resolver" dclr

pub enum OwnerState u8(
    LIVE,
    CONSUMED,
    MAYBE_CONSUMED,
    BORROWED,
)

OwnerFact(
    declaration dclr.Decl*
    state OwnerState
    conditional bool
    condition dclr.Decl*
)

OwnerFactArray(
    data OwnerFact*
    length u64
    capacity u64
)

DeferAction(
    expression nt.Expr*
    body nt.Stmt*
    conditional bool
    scope u64
)

ErrorAction(
    expression nt.Expr*
    body nt.Stmt*
    conditional bool
    scope u64
)

Flow(
    facts OwnerFactArray
    deferred nt.NodeArray[DeferAction]
    onErrors nt.NodeArray[ErrorAction]
    provenance nt.NodeArray[PointerFact]
    terminated bool
)

PointerFact(
    destination dclr.Decl*
    source dclr.Decl*
    stackSlice bool
    uncertain bool
)

PointerSummary(
    function dclr.Decl*
    returnedParameter dclr.Decl*
    stackSource dclr.Decl*
    returnsStackStorage bool
    ambiguous bool
)

Analyzer(
    file fctx.FileCtx*
    destructible dclr.DeclArray
    destructorMethods dclr.DeclArray
    pointerSummaries nt.NodeArray[PointerSummary]
    diagnostics ls.List[comperr.CompErr]
    hasErrors bool
    scope u64
    returnOwned bool
    genericSpecialization bool
)

emptyFacts() OwnerFactArray:
    ret OwnerFactArray(data=none, length=0, capacity=0)
..

OwnerFactArray.get(index u64) !OwnerFact:
    if index >= this.length:
        throw "ownership fact index out of bounds"
    ..
    unsafe: ret this.data[index] ..
..

OwnerFactArray.set(index u64, fact OwnerFact) !void:
    if index >= this.length:
        throw "ownership fact index out of bounds"
    ..
    unsafe: this.data[index] = fact ..
..

OwnerFactArray.remove(index u64) !void:
    if index >= this.length:
        ret
    ..
    if index + 1 < this.length:
        for i := index to this.length - 1:
            next := try this.get(i + 1)
            try this.set(i, next)
        ..
    ..
    this.length = this.length - 1
..

OwnerFactArray.push(fact OwnerFact) !void:
    if this.length == this.capacity:
        nextCapacity u64 = 8
        if this.capacity != 0: nextCapacity = this.capacity * 2 ..
        if this.data == none:
            this.data = try ctx.alloc.allocT[OwnerFact](nextCapacity)
        else:
            this.data = try ctx.alloc.reallocT[OwnerFact](this.data, nextCapacity)
        ..
        this.capacity = nextCapacity
    ..
    unsafe: this.data[this.length] = fact ..
    this.length = this.length + 1
..

cloneFlow(input Flow) !Flow:
    output := Flow(facts=emptyFacts(), deferred=nt.emptyNodeArray[DeferAction](), onErrors=nt.emptyNodeArray[ErrorAction](), provenance=nt.emptyNodeArray[PointerFact](), terminated=input.terminated)
    for i := 0 to input.facts.length:
        try output.facts.push(try input.facts.get(i))
    ..
    for i := 0 to input.deferred.count():
        try output.deferred.pushRight(ctx.alloc, try input.deferred.get(i))
    ..
    for i := 0 to input.onErrors.count():
        try output.onErrors.pushRight(ctx.alloc, try input.onErrors.get(i))
    ..
    for i := 0 to input.provenance.count():
        try output.provenance.pushRight(ctx.alloc, try input.provenance.get(i))
    ..
    ret output
..

cloneFlowFromPointer(input Flow*) !Flow:
    unsafe:
        ret try cloneFlow(*input)
    ..
..

findFact(flow Flow*, declaration dclr.Decl*, index u64*) bool:
    for i := 0 to flow.facts.length:
        fact OwnerFact
        unsafe: fact = flow.facts.data[i] ..
        if fact.declaration == declaration:
            unsafe: *index = i ..
            ret true
        ..
    ..
    ret false
..

findPointerFact(flow Flow*, declaration dclr.Decl*, index u64*) bool:
    for i := 0 to flow.provenance.count():
        fact PointerFact
        unsafe: fact = flow.provenance.data[i] ..
        if fact.destination == declaration:
            unsafe: *index = i ..
            ret true
        ..
    ..
    ret false
..

setPointerFact(flow Flow*, destination dclr.Decl*, source dclr.Decl*, stackSlice bool) !void:
    if destination == none:
        ret
    ..
    index u64
    fact := PointerFact(destination=destination, source=source, stackSlice=stackSlice, uncertain=false)
    if findPointerFact(flow, destination, addrof index):
        try flow.provenance.set(index, fact)
    else:
        try flow.provenance.pushRight(ctx.alloc, fact)
    ..
..

localStorage(declaration dclr.Decl*) !bool:
    if declaration == none: ret false ..
    match declaration.kind as kind:
    case dclr.DeclKind.Variable:
        if kind.isGlobal || declaration.owner.scope == 0: ret false ..
        scope := try declaration.module.getScope(declaration.owner.scope)
        match scope.kind as scopeKind:
        case dclr.ScopeKind.Function: ret true
        case dclr.ScopeKind.Method: ret true
        case dclr.ScopeKind.Block: ret true
        ..
        ret false
    case dclr.DeclKind.Argument:
        # A pointer or slice argument refers to caller-owned storage. Returning
        # a projection of it does not escape this function's own stack frame.
        if pointerOrSlice(declaration.declType): ret false ..
        ret true
    else: ret false
    ..
..

pointerSource(a Analyzer*, flow Flow*, expression nt.Expr*, source dclr.Decl**, stackSlice bool*) !bool:
    if expression == none: ret false ..
    match expression as value:
    case nt.Expr.Array:
        unsafe: *stackSlice = true ..
        ret true
    case nt.Expr.Unary:
        if value.op == tkt.KwType.ADDROF || value.op == tkt.KwType.AMPERSAND:
            match value.operand as address:
            case nt.Expr.Named:
                if address.decl != none:
                    unsafe: *source = address.decl ..
                    ret true
                ..
            case nt.Expr.MemberAccess:
                ownerType := expressionType(address.owner)
                match ownerType as typeKind:
                case nt.Type.Pointer:
                    ret false
                else:
                    root := placeRoot(address.owner)
                    if root != none:
                        unsafe: *source = root ..
                        ret true
                    ..
                ..
            case nt.Expr.Subscript:
                root := placeRoot(address.owner)
                index u64
                if findPointerFact(flow, root, addrof index):
                    fact := try flow.provenance.get(index)
                    if fact.stackSlice:
                        unsafe:
                            *source = fact.source
                            *stackSlice = true
                        ..
                        ret true
                    ..
                ..
                ret false
            else:
                ret false
            ..
        ..
        ret false
    case nt.Expr.Named:
        if value.decl != none:
            index u64
            if findPointerFact(flow, value.decl, addrof index):
                fact := try flow.provenance.get(index)
                unsafe:
                    *source = fact.source
                    *stackSlice = fact.stackSlice
                ..
                ret true
            ..
        ..
        ret false
    case nt.Expr.Move:
        ret try pointerSource(a, flow, value.operand, source, stackSlice)
    case nt.Expr.Try:
        ret try pointerSource(a, flow, value.call, source, stackSlice)
    case nt.Expr.DirectCall:
        ret try pointerCallSource(a, flow, value.decl, value.args, source, stackSlice)
    case nt.Expr.TemplatedDirectCall:
        ret try pointerCallSource(a, flow, value.decl, value.args, source, stackSlice)
    case nt.Expr.IndirectCall:
        ret try pointerCallSource(a, flow, value.target, value.args, source, stackSlice)
    case nt.Expr.TemplatedIndirectCall:
        ret try pointerCallSource(a, flow, value.target, value.args, source, stackSlice)
    else:
        ret false
    ..
..

pointerCallSource(a Analyzer*, flow Flow*, function dclr.Decl*, arguments nt.NodeArray[nt.Expr*], source dclr.Decl**, stackSlice bool*) !bool:
    if function == none: ret false ..
    # Return-origin summaries are recorded during the destructor inventory
    # traversal. Resolve the formal parameter to the actual call argument.
    for i := 0 to a.pointerSummaries.count():
        summary := try a.pointerSummaries.get(i)
        if summary.function == function:
            if summary.returnsStackStorage:
                unsafe:
                    *source = summary.stackSource
                    *stackSlice = true
                ..
                ret true
            ..
            if summary.ambiguous || summary.returnedParameter == none || function.sourceHeader == none:
                ret false
            ..
            for j := 0 to function.sourceHeader.fields.count():
                formal := try function.sourceHeader.fields.get(j)
                match formal as parameter:
                case nt.Expr.VarDef:
                    if parameter.decl == summary.returnedParameter && j < arguments.count():
                        ret try pointerSource(a, flow, try arguments.get(j), source, stackSlice)
                    ..
                else:
                    continue
                ..
            ..
        ..
    ..
    ret false
..

pointerOrSlice(value nt.Type*) bool:
    if value == none: ret false ..
    match value as kind:
    case nt.Type.Pointer: ret true
    case nt.Type.Slice: ret true
    case nt.Type.Owned: ret pointerOrSlice(kind.ofType)
    case nt.Type.Throwing: ret pointerOrSlice(kind.ofType)
    else: ret false
    ..
..

recordPointerValue(a Analyzer*, flow Flow*, destination dclr.Decl*, value nt.Expr*, destinationType nt.Type*) !void:
    if destination == none || not pointerOrSlice(destinationType):
        ret
    ..
    source dclr.Decl* = none
    stackSlice := false
    if try pointerSource(a, flow, value, addrof source, addrof stackSlice):
        try setPointerFact(flow, destination, source, stackSlice)
    ..
..

checkPointerEscape(a Analyzer*, flow Flow*, expression nt.Expr*, returnPosition org.FilePos) !void:
    if not pointerOrSlice(expressionType(expression)):
        ret
    ..
    source dclr.Decl* = none
    stackSlice := false
    if try pointerSource(a, flow, expression, addrof source, addrof stackSlice):
        if stackSlice || try localStorage(source):
            related fctx.FileCtx* = none
            relatedPosition := org.FilePos(line=0, column=0)
            if source != none && (source.sourcePos.line != 0 || source.sourcePos.column != 0):
                related = a.file
                relatedPosition = source.sourcePos
            ..
            try diagnoseRelated(a, "POINTER_LOCAL_ESCAPE", "return value may point into storage owned by this function", returnPosition, related, relatedPosition, true)
        ..
    ..
..

declTracked(a Analyzer*, declaration dclr.Decl*) bool:
    for i := 0 to a.destructible.count():
        owner dclr.Decl*
        unsafe: owner = a.destructible.data[i] ..
        if owner == declaration:
            ret true
        ..
    ..
    ret false
..

trackedType(a Analyzer*, value nt.Type*, depth u64) bool:
    if value == none || depth > 32: ret false ..
    match value as kind:
    case nt.Type.Owned:
        ret trackedType(a, kind.ofType, depth + 1)
    case nt.Type.Throwing:
        ret trackedType(a, kind.ofType, depth + 1)
    case nt.Type.Templated:
        ret trackedType(a, kind.owner, depth + 1)
    case nt.Type.Named:
        if kind.primitive == nt.PrimitiveType.String: ret true ..
        if kind.decl == none: ret false ..
        if declTracked(a, kind.decl): ret true ..
        match kind.decl.kind as declKind:
        case dclr.DeclKind.Alias:
            ret trackedType(a, declKind.target, depth + 1)
        else:
            ret false
        ..
    else:
        ret false
    ..
..

isOwned(value nt.Type*) bool:
    if value == none: ret false ..
    match value as kind:
    case nt.Type.Owned: ret true
    else: ret false
    ..
..

ownedResult(value nt.Type*, depth u64) bool:
    if value == none || depth > 32: ret false ..
    match value as kind:
    case nt.Type.Owned: ret true
    case nt.Type.Throwing: ret ownedResult(kind.ofType, depth + 1)
    else: ret false
    ..
..

freshOwnerExpression(expression nt.Expr*) bool:
    if expression == none: ret false ..
    match expression as value:
    case nt.Expr.Try: ret freshOwnerExpression(value.call)
    case nt.Expr.DirectCall:
        ret value.callKind == nt.CallKind.StructConstructor || value.callKind == nt.CallKind.UnionConstructor
    case nt.Expr.TemplatedDirectCall:
        ret value.callKind == nt.CallKind.StructConstructor || value.callKind == nt.CallKind.UnionConstructor
    case nt.Expr.IndirectCall:
        ret value.callKind == nt.CallKind.StructConstructor || value.callKind == nt.CallKind.UnionConstructor
    case nt.Expr.TemplatedIndirectCall:
        ret value.callKind == nt.CallKind.StructConstructor || value.callKind == nt.CallKind.UnionConstructor
    else:
        ret false
    ..
..

explicitMove(expression nt.Expr*) bool:
    if expression == none: ret false ..
    match expression as value:
    case nt.Expr.Move: ret true
    else: ret false
    ..
..

isDiscardedOwner(expression nt.Expr*) bool:
    if expression == none || not ownedResult(expressionType(expression), 0): ret false ..
    match expression as value:
    case nt.Expr.DirectCall: ret true
    case nt.Expr.TemplatedDirectCall: ret true
    case nt.Expr.IndirectCall: ret true
    case nt.Expr.TemplatedIndirectCall: ret true
    case nt.Expr.Try: ret true
    else: ret false
    ..
..

isStringType(value nt.Type*) bool:
    if value == none: ret false ..
    match value as kind:
    case nt.Type.Owned: ret isStringType(kind.ofType)
    case nt.Type.Named: ret kind.primitive == nt.PrimitiveType.String
    else: ret false
    ..
..

isThrowingType(value nt.Type*, depth u64) bool:
    if value == none || depth > 32: ret false ..
    match value as kind:
    case nt.Type.Throwing: ret true
    case nt.Type.Owned: ret isThrowingType(kind.ofType, depth + 1)
    else: ret false
    ..
..

expressionType(expression nt.Expr*) nt.Type*:
    if expression == none: ret none ..
    match expression as value:
    case nt.Expr.Literal: ret value.type
    case nt.Expr.Named: ret value.type
    case nt.Expr.MemberAccess: ret value.type
    case nt.Expr.Subscript: ret value.type
    case nt.Expr.Array: ret value.type
    case nt.Expr.VarDef: ret value.type
    case nt.Expr.VarDefAssign: ret value.type
    case nt.Expr.VarDefAssignDestructure: ret value.type
    case nt.Expr.Sizeof: ret value.type
    case nt.Expr.Unary: ret value.type
    case nt.Expr.Move: ret value.type
    case nt.Expr.Binary: ret value.type
    case nt.Expr.DirectCall: ret value.type
    case nt.Expr.TemplatedDirectCall: ret value.type
    case nt.Expr.IndirectCall: ret value.type
    case nt.Expr.TemplatedIndirectCall: ret value.type
    case nt.Expr.Try: ret value.type
    case nt.Expr.Assign: ret value.type
    case nt.Expr.InlineLLVM: ret value.type
    else: ret none
    ..
..

expressionPosition(expression nt.Expr*) org.FilePos:
    if expression == none: ret org.FilePos(line=0, column=0) ..
    match expression as value:
    case nt.Expr.DirectCall: ret value.sourcePos
    case nt.Expr.TemplatedDirectCall: ret value.sourcePos
    case nt.Expr.IndirectCall: ret value.sourcePos
    case nt.Expr.TemplatedIndirectCall: ret value.sourcePos
    case nt.Expr.Assign: ret value.sourcePos
    case nt.Expr.Return: ret value.sourcePos
    case nt.Expr.Throw: ret value.sourcePos
    case nt.Expr.VarDefAssign: ret value.sourcePos
    case nt.Expr.Named: ret value.sourcePos
    case nt.Expr.Try: ret expressionPosition(value.call)
    else: ret org.FilePos(line=0, column=0)
    ..
..

statementPosition(statement nt.Stmt*) !org.FilePos:
    if statement == none: ret org.FilePos(line=0, column=0) ..
    match statement as value:
    case nt.Stmt.Expression: ret expressionPosition(value.expr)
    case nt.Stmt.If: ret value.sourcePos
    case nt.Stmt.Elif: ret value.sourcePos
    case nt.Stmt.Loop: ret value.sourcePos
    case nt.Stmt.Body:
        if value.statements.count() > 0:
            ret try statementPosition(try value.statements.get(value.statements.count() - 1))
        ..
    case nt.Stmt.ForLoop:
        ret try statementPosition(value.body)
    case nt.Stmt.Bounded: ret try statementPosition(value.body)
    case nt.Stmt.Unsafe: ret try statementPosition(value.body)
    case nt.Stmt.Defer: ret try statementPosition(value.body)
    case nt.Stmt.OnError: ret try statementPosition(value.body)
    case nt.Stmt.Else: ret try statementPosition(value.body)
    else: ret org.FilePos(line=0, column=0)
    ..
    ret org.FilePos(line=0, column=0)
..

diagnose(a Analyzer*, code str, message str, position org.FilePos, warning bool) !void:
    ret try diagnoseRelated(a, code, message, position, none, org.FilePos(line=0, column=0), warning)
..

diagnoseRelated(a Analyzer*, code str, message str, position org.FilePos, relatedFile fctx.FileCtx*, relatedPos org.FilePos, warning bool) !void:
    for i := 0 to a.diagnostics.count():
        prior := try a.diagnostics.get(i)
        if a.genericSpecialization && prior.file.path == a.file.path && prior.code == code && prior.org.position.line == position.line && prior.org.position.column == position.column:
            ret
        ..
        if prior.code == code && prior.org.position.line == position.line && prior.org.position.column == position.column && prior.relatedFile == relatedFile && prior.relatedPos.line == relatedPos.line && prior.relatedPos.column == relatedPos.column:
            ret
        ..
    ..
    severity := comperr.Severity.ERROR
    if warning: severity = comperr.Severity.WARNING ..
    diagnostic := comperr.CompErr(
        file=a.file,
        org=org.Origin(filePath=a.file.path, position=position),
        relatedFile=relatedFile,
        relatedPos=relatedPos,
        code=code,
        msg=message,
        help="",
        sev=severity,
    )
    try a.diagnostics.pushRight(diagnostic)
    if not warning: a.hasErrors = true ..
..

addOwner(flow Flow*, declaration dclr.Decl*, state OwnerState, conditional bool, condition dclr.Decl*) !void:
    index u64
    if findFact(flow, declaration, addrof index):
        try flow.facts.set(index, OwnerFact(declaration=declaration, state=state, conditional=conditional, condition=condition))
    else:
        try flow.facts.push(OwnerFact(declaration=declaration, state=state, conditional=conditional, condition=condition))
    ..
..

setOwnerState(flow Flow*, declaration dclr.Decl*, state OwnerState) !void:
    index u64
    if findFact(flow, declaration, addrof index):
        fact := try flow.facts.get(index)
        fact.state = state
        fact.conditional = false
        fact.condition = none
        try flow.facts.set(index, fact)
    ..
..

placeRoot(expression nt.Expr*) dclr.Decl*:
    if expression == none: ret none ..
    match expression as kind:
    case nt.Expr.Named:
        ret kind.decl
    case nt.Expr.MemberAccess:
        ret placeRoot(kind.owner)
    case nt.Expr.Subscript:
        ret placeRoot(kind.owner)
    case nt.Expr.Unary:
        ret placeRoot(kind.operand)
    case nt.Expr.Move:
        ret placeRoot(kind.operand)
    else:
        ret none
    ..
..

directPlace(expression nt.Expr*) dclr.Decl*:
    if expression == none: ret none ..
    match expression as value:
    case nt.Expr.Named: ret value.decl
    else: ret none
    ..
..

isFieldDeclaration(declaration dclr.Decl*) bool:
    if declaration == none: ret false ..
    match declaration.kind as kind:
    case dclr.DeclKind.Field: ret true
    else: ret false
    ..
..

isGlobalStorage(declaration dclr.Decl*) bool:
    if declaration == none: ret false ..
    if declaration.isModuleVariable: ret true ..
    match declaration.kind as kind:
    case dclr.DeclKind.Variable: ret kind.isGlobal
    else: ret false
    ..
..

isDestructor(a Analyzer*, declaration dclr.Decl*) bool:
    if declaration == none: ret false ..
    # `str.free` lives in the implicit core module, whose source FileCtx is not
    # necessarily present in the user import graph.
    if isStringType(declaration.methodOwnerType):
        match declaration.kind as stringMethod:
        case dclr.DeclKind.Function:
            if stringMethod.name == "str.free": ret true ..
        else:
            ret false
        ..
    ..
    for i := 0 to a.destructorMethods.count():
        method dclr.Decl*
        unsafe: method = a.destructorMethods.data[i] ..
        if method == declaration: ret true ..
    ..
    ret false
..

isImplicitStringDestructor(ownerExpression nt.Expr*, memberExpression nt.Expr*) bool:
    match memberExpression as member:
    case nt.Expr.Named:
        if member.name != "free": ret false ..
    else:
        ret false
    ..
    returnType := expressionType(ownerExpression)
    ret isStringType(returnType)
..

cleanupReceiver(a Analyzer*, expression nt.Expr*) !dclr.Decl*:
    if expression == none: ret none ..
    match expression as value:
    case nt.Expr.DirectCall:
        if isDestructor(a, value.decl) && value.args.count() > 0:
            ret placeRoot(try value.args.get(0))
        ..
    case nt.Expr.TemplatedDirectCall:
        if isDestructor(a, value.decl) && value.args.count() > 0:
            ret placeRoot(try value.args.get(0))
        ..
    case nt.Expr.IndirectCall:
        match value.owner as owner:
        case nt.Expr.MemberAccess:
            if isDestructor(a, value.target) || isImplicitStringDestructor(owner.owner, owner.member):
                ret placeRoot(owner.owner)
            ..
        else:
            ret none
        ..
    case nt.Expr.TemplatedIndirectCall:
        match value.owner as owner:
        case nt.Expr.MemberAccess:
            if isDestructor(a, value.target) || isImplicitStringDestructor(owner.owner, owner.member):
                ret placeRoot(owner.owner)
            ..
        else:
            ret none
        ..
    else:
        ret none
    ..
    ret none
..

runCleanupExpression(a Analyzer*, flow Flow*, expression nt.Expr*) !void:
    receiver := try cleanupReceiver(a, expression)
    if receiver != none:
        try setOwnerState(flow, receiver, OwnerState.CONSUMED)
    ..
    if expression != none: try readExpression(a, flow, expression, false) ..
..

readCallArgument(a Analyzer*, flow Flow*, argument nt.Expr*, expectedOwned bool, constructor bool) !void:
    if constructor:
        match argument as namedArgument:
        case nt.Expr.Assign:
            # Named constructor arguments target aggregate fields. Analyze the
            # value transfer without treating the field declaration as a local
            # place owned by this function.
            try readExpression(a, flow, namedArgument.expr, expectedOwned)
        else:
            try readExpression(a, flow, argument, expectedOwned)
        ..
    else:
        try readExpression(a, flow, argument, expectedOwned)
    ..
..

hasPendingDeferredCleanup(a Analyzer*, flow Flow*, declaration dclr.Decl*) !bool:
    for i := 0 to flow.deferred.count():
        action := try flow.deferred.get(i)
        receiver := try cleanupReceiver(a, action.expression)
        if receiver == declaration:
            ret true
        ..
    ..
    ret false
..

checkUse(a Analyzer*, flow Flow*, declaration dclr.Decl*, position org.FilePos) !void:
    index u64
    if not findFact(flow, declaration, addrof index):
        ret
    ..
    fact := try flow.facts.get(index)
    if fact.state == OwnerState.CONSUMED:
        try diagnose(a, "OWNERSHIP_USE_AFTER_MOVE", "use of a value after ownership was transferred", position, false)
    elif fact.state == OwnerState.MAYBE_CONSUMED:
        # Keep uncertain joins visible while the loop and nested-scope solver
        # converges on legacy parity; this state alone is not proof of misuse.
        try diagnoseRelated(a, "OWNERSHIP_MAYBE_MOVED", "value may have been moved on another control-flow path", declaration.sourcePos, a.file, position, true)
    ..
..

readExpression(a Analyzer*, flow Flow*, expression nt.Expr*, moving bool) !void:
    if expression == none:
        ret
    ..
    match expression as value:
    case nt.Expr.Named:
        if value.decl != none:
            if moving:
                if try hasPendingDeferredCleanup(a, flow, value.decl):
                    try diagnoseRelated(a, "OWNERSHIP_TRANSFER_DEFERRED", "value is transferred while a deferred destructor is still pending", value.decl.sourcePos, a.file, value.sourcePos, false)
                ..
                index u64
                if findFact(flow, value.decl, addrof index):
                    fact := try flow.facts.get(index)
                    if fact.state == OwnerState.BORROWED:
                        # Some current generic library APIs intentionally route
                        # borrowed values through unsafe transfer wrappers. Keep
                        # the finding visible for review rather than failing the
                        # compiler until those contracts are modeled explicitly.
                        try diagnoseRelated(a, "OWNERSHIP_MOVE_BORROWED", "cannot move a borrowed value", value.decl.sourcePos, a.file, value.sourcePos, true)
                    elif fact.state == OwnerState.CONSUMED || fact.state == OwnerState.MAYBE_CONSUMED:
                        try checkUse(a, flow, value.decl, value.sourcePos)
                        if fact.state == OwnerState.MAYBE_CONSUMED:
                            # This transfer consumes the value on the current
                            # path even though the join made its prior state
                            # uncertain. Preserve the maybe-moved finding, but
                            # do not later report the same path as a leak.
                            try setOwnerState(flow, value.decl, OwnerState.CONSUMED)
                        ..
                    else:
                        try setOwnerState(flow, value.decl, OwnerState.CONSUMED)
                    ..
                ..
            else:
                try checkUse(a, flow, value.decl, value.sourcePos)
            ..
        ..
    case nt.Expr.Move:
        try readExpression(a, flow, value.operand, true)
    case nt.Expr.MemberAccess:
        try readExpression(a, flow, value.owner, false)
    case nt.Expr.Subscript:
        try readExpression(a, flow, value.owner, false)
        try readExpression(a, flow, value.index, false)
    case nt.Expr.Unary:
        try readExpression(a, flow, value.operand, false)
    case nt.Expr.Binary:
        try readExpression(a, flow, value.left, false)
        try readExpression(a, flow, value.right, false)
    case nt.Expr.DirectCall:
        directDestructor := isDestructor(a, value.decl)
        constructor := value.callKind == nt.CallKind.StructConstructor || value.callKind == nt.CallKind.UnionConstructor
        for i := 0 to value.args.count():
            argument := try value.args.get(i)
            if directDestructor && i == 0:
                receiver := placeRoot(argument)
                if receiver != none: try setOwnerState(flow, receiver, OwnerState.CONSUMED) ..
                try readCallArgument(a, flow, argument, false, constructor)
                continue
            ..
            expectedOwned := false
            if value.decl != none:
                match value.decl.kind as target:
                case dclr.DeclKind.Function:
                    if i < target.args.count():
                        formal := try target.args.get(i)
                        expectedOwned = isOwned(formal.declType)
                    ..
                else:
                    expectedOwned = false
                ..
            ..
            try readCallArgument(a, flow, argument, expectedOwned, constructor)
        ..
    case nt.Expr.TemplatedDirectCall:
        directDestructor := isDestructor(a, value.decl)
        constructor := value.callKind == nt.CallKind.StructConstructor || value.callKind == nt.CallKind.UnionConstructor
        for i := 0 to value.args.count():
            argument := try value.args.get(i)
            if directDestructor && i == 0:
                receiver := placeRoot(argument)
                if receiver != none: try setOwnerState(flow, receiver, OwnerState.CONSUMED) ..
                try readCallArgument(a, flow, argument, false, constructor)
                continue
            ..
            expectedOwned := false
            if value.decl != none:
                match value.decl.kind as target:
                case dclr.DeclKind.Function:
                    if i < target.args.count():
                        formal := try target.args.get(i)
                        expectedOwned = isOwned(formal.declType)
                    ..
                else:
                    expectedOwned = false
                ..
            ..
            try readCallArgument(a, flow, argument, expectedOwned, constructor)
        ..
    case nt.Expr.IndirectCall:
        isStringFree := false
        match value.owner as callOwner:
        case nt.Expr.MemberAccess:
            isStringFree = isImplicitStringDestructor(callOwner.owner, callOwner.member)
        else:
            isStringFree = false
        ..
        if isDestructor(a, value.target) || isStringFree:
            match value.owner as owner:
            case nt.Expr.MemberAccess:
                directReceiver := directPlace(owner.owner)
                if directReceiver != none: try setOwnerState(flow, directReceiver, OwnerState.CONSUMED) ..
            else:
                flow = flow
            ..
        else:
            try readExpression(a, flow, value.owner, false)
        ..
        for i := 0 to value.args.count():
            expectedOwned := false
            if value.target != none:
                match value.target.kind as target:
                case dclr.DeclKind.Function:
                    if i < target.args.count():
                        formal := try target.args.get(i)
                        expectedOwned = isOwned(formal.declType)
                    ..
                else:
                    expectedOwned = false
                ..
            ..
            try readExpression(a, flow, value.args.get(i), expectedOwned)
        ..
    case nt.Expr.TemplatedIndirectCall:
        templatedStringFree := false
        match value.owner as callOwner:
        case nt.Expr.MemberAccess:
            templatedStringFree = isImplicitStringDestructor(callOwner.owner, callOwner.member)
        else:
            templatedStringFree = false
        ..
        if isDestructor(a, value.target) || templatedStringFree:
            match value.owner as owner:
            case nt.Expr.MemberAccess:
                directReceiver := directPlace(owner.owner)
                if directReceiver != none: try setOwnerState(flow, directReceiver, OwnerState.CONSUMED) ..
            else:
                flow = flow
            ..
        else:
            try readExpression(a, flow, value.owner, false)
        ..
        for i := 0 to value.args.count():
            expectedOwned := false
            if value.target != none:
                match value.target.kind as target:
                case dclr.DeclKind.Function:
                    if i < target.args.count():
                        formal := try target.args.get(i)
                        expectedOwned = isOwned(formal.declType)
                    ..
                else:
                    expectedOwned = false
                ..
            ..
            try readExpression(a, flow, value.args.get(i), expectedOwned)
        ..
    case nt.Expr.Try:
        try readExpression(a, flow, value.call, false)
        if isThrowingType(expressionType(value.call), 0):
            try checkThrowingFailure(a, flow, expressionPosition(value.call))
        ..
    case nt.Expr.Assign:
        try readExpression(a, flow, value.expr, false)
        root := directPlace(value.assignee)
        if root != none:
            try recordPointerValue(a, flow, root, value.expr, root.declType)
        ..
        if root != none && not isFieldDeclaration(root) && trackedType(a, root.declType, 0):
            index u64
            if findFact(flow, root, addrof index):
                old := try flow.facts.get(index)
                if old.state == OwnerState.LIVE || old.state == OwnerState.MAYBE_CONSUMED:
                    try diagnose(a, "OWNERSHIP_OVERWRITE", "assignment replaces an owner before it is consumed", value.sourcePos, true)
                ..
            ..
            if isGlobalStorage(root):
                # Ownership stored in module/global storage outlives this
                # function; it is transferred out of the local flow state.
                try setOwnerState(flow, root, OwnerState.CONSUMED)
            elif ownedResult(expressionType(value.expr), 0) || freshOwnerExpression(value.expr) || explicitMove(value.expr):
                try addOwner(flow, root, OwnerState.LIVE, false, none)
            else:
                try setOwnerState(flow, root, OwnerState.BORROWED)
            ..
        ..
    case nt.Expr.VarDef:
        if value.decl != none && trackedType(a, value.type, 0) && isOwned(value.type):
            # A declaration without an initializer creates storage, not an
            # initialized resource. The first assignment establishes ownership.
            try addOwner(flow, value.decl, OwnerState.CONSUMED, false, none)
        ..
    case nt.Expr.VarDefAssign:
        try readExpression(a, flow, value.assignment, false)
        try recordPointerValue(a, flow, value.decl, value.assignment, value.type)
        if value.decl != none && trackedType(a, value.type, 0) && (ownedResult(value.type, 0) || ownedResult(expressionType(value.assignment), 0) || freshOwnerExpression(value.assignment) || explicitMove(value.assignment)):
            try addOwner(flow, value.decl, OwnerState.LIVE, false, none)
        ..
    case nt.Expr.VarDefAssignDestructure:
        try readExpression(a, flow, value.call, false)
        # Destructuring a throwing result captures the error value. Control
        # continues so the caller can inspect it; only `try` and `throw`
        # create unconditional error-exit edges.
        if value.valueDecl != none && trackedType(a, value.type, 0) && (ownedResult(value.type, 0) || ownedResult(expressionType(value.call), 0)):
            try addOwner(flow, value.valueDecl, OwnerState.LIVE, true, value.errorDecl)
        ..
    case nt.Expr.Array:
        try readExpression(a, flow, value.length, false)
    case nt.Expr.Return:
        try checkPointerEscape(a, flow, value.expr, value.sourcePos)
        shouldMove := a.returnOwned || ownedResult(expressionType(value.expr), 0)
        try readExpression(a, flow, value.expr, shouldMove)
        try checkExit(a, flow, value.sourcePos)
        flow.terminated = true
    case nt.Expr.Throw:
        try readExpression(a, flow, value.expr, false)
        try checkThrowingFailure(a, flow, value.sourcePos)
        flow.terminated = true
    case nt.Expr.InlineLLVM:
        for i := 0 to value.args.count():
            try readExpression(a, flow, value.args.get(i), false)
        ..
    else:
        ret
    ..
..

booleanLiteral(expression nt.Expr*, value bool*) bool:
    if expression == none: ret false ..
    match expression as node:
    case nt.Expr.Literal:
        match node.literal as literal:
        case nt.Literal.Boolean:
            unsafe: *value = literal.value ..
            ret true
        else:
            ret false
        ..
    else:
        ret false
    ..
..

invertPredicate(value u8) u8:
    if value == 1: ret 2 ..
    if value == 2: ret 1 ..
    ret 0
..

zeroLiteral(expression nt.Expr*) bool:
    if expression == none: ret false ..
    match expression as value:
    case nt.Expr.Literal:
        match value.literal as literal:
        case nt.Literal.Number: ret literal.value == "0"
        case nt.Literal.HexNumber: ret literal.value == "0x0"
        else: ret false
        ..
    else:
        ret false
    ..
..

errorCodeField(expression nt.Expr*, errorDecl dclr.Decl*) bool:
    if expression == none: ret false ..
    match expression as value:
    case nt.Expr.MemberAccess:
        if placeRoot(value.owner) != errorDecl: ret false ..
        match value.member as member:
        case nt.Expr.Named: ret member.name == "code" || member.name == "__code"
        else: ret false
        ..
    else:
        ret false
    ..
..

predicateKind(expression nt.Expr*, errorDecl dclr.Decl*) u8:
    if expression == none: ret 0 ..
    match expression as value:
    case nt.Expr.IndirectCall:
        match value.owner as owner:
        case nt.Expr.MemberAccess:
            if placeRoot(owner.owner) != errorDecl: ret 0 ..
            match owner.member as member:
            case nt.Expr.Named:
                if member.name == "ok": ret 1 ..
                if member.name == "nok": ret 2 ..
                ret 0
            else:
                ret 0
            ..
        else:
            ret 0
        ..
    case nt.Expr.Unary:
        if value.op == tkt.KwType.NOT:
            ret invertPredicate(predicateKind(value.operand, errorDecl))
        ..
        ret 0
    case nt.Expr.Binary:
        if value.op == tkt.KwType.CMP_EQ || value.op == tkt.KwType.CMP_NEQ:
            if errorCodeField(value.left, errorDecl) && zeroLiteral(value.right):
                if value.op == tkt.KwType.CMP_EQ: ret 1 ..
                ret 2
            ..
            if errorCodeField(value.right, errorDecl) && zeroLiteral(value.left):
                if value.op == tkt.KwType.CMP_EQ: ret 1 ..
                ret 2
            ..
            success := false
            leftPredicate := predicateKind(value.left, errorDecl)
            if leftPredicate == 0 && booleanLiteral(value.left, addrof success):
                rightPredicate := predicateKind(value.right, errorDecl)
                if rightPredicate != 0:
                    if (value.op == tkt.KwType.CMP_EQ) == success: ret rightPredicate ..
                    ret invertPredicate(rightPredicate)
                ..
            ..
            rightValue := false
            rightPredicate := predicateKind(value.right, errorDecl)
            if rightPredicate == 0 && booleanLiteral(value.right, addrof rightValue):
                if leftPredicate != 0:
                    if (value.op == tkt.KwType.CMP_EQ) == rightValue: ret leftPredicate ..
                    ret invertPredicate(leftPredicate)
                ..
            ..
        ..
        ret 0
    else:
        ret 0
    ..
..

refineConditional(flow Flow*, errorDecl dclr.Decl*, success bool) !void:
    for i := 0 to flow.facts.length:
        fact := try flow.facts.get(i)
        if fact.conditional && fact.condition == errorDecl:
            fact.state = OwnerState.CONSUMED
            if success: fact.state = OwnerState.LIVE ..
            fact.conditional = false
            fact.condition = none
            try flow.facts.set(i, fact)
        ..
    ..
..

mergeFlow(target Flow*, other Flow*) !void:
    if other.terminated:
        ret
    ..
    for i := 0 to target.facts.length:
        left := try target.facts.get(i)
        rightIndex u64
        if findFact(other, left.declaration, addrof rightIndex):
            right := try other.facts.get(rightIndex)
            if left.state != right.state || left.conditional != right.conditional:
                left.state = OwnerState.MAYBE_CONSUMED
                left.conditional = left.conditional || right.conditional
                if left.condition != right.condition: left.condition = none ..
                try target.facts.set(i, left)
            ..
        else:
            if left.state != OwnerState.BORROWED:
                left.state = OwnerState.MAYBE_CONSUMED
                try target.facts.set(i, left)
            ..
        ..
    ..
    for i := 0 to other.facts.length:
        right := try other.facts.get(i)
        leftIndex u64
        if not findFact(target, right.declaration, addrof leftIndex):
            right.state = OwnerState.MAYBE_CONSUMED
            try target.facts.push(right)
        ..
    ..
    for i := 0 to other.deferred.count():
        action := try other.deferred.get(i)
        found := false
        for j := 0 to target.deferred.count():
            prior := try target.deferred.get(j)
            if prior.expression == action.expression && prior.body == action.body:
                found = true
                break
            ..
        ..
        if not found:
            action.conditional = true
            try target.deferred.pushRight(ctx.alloc, action)
        ..
    ..
    for i := 0 to target.deferred.count():
        prior := try target.deferred.get(i)
        found := false
        for j := 0 to other.deferred.count():
            otherAction := try other.deferred.get(j)
            if prior.expression == otherAction.expression && prior.body == otherAction.body:
                found = true
                break
            ..
        ..
        if not found:
            prior.conditional = true
            try target.deferred.set(i, prior)
        ..
    ..
    for i := 0 to other.onErrors.count():
        action := try other.onErrors.get(i)
        found := false
        for j := 0 to target.onErrors.count():
            prior := try target.onErrors.get(j)
            if prior.expression == action.expression && prior.body == action.body:
                found = true
                break
            ..
        ..
        if not found:
            action.conditional = true
            try target.onErrors.pushRight(ctx.alloc, action)
        ..
    ..
    for i := 0 to target.onErrors.count():
        prior := try target.onErrors.get(i)
        found := false
        for j := 0 to other.onErrors.count():
            otherAction := try other.onErrors.get(j)
            if prior.expression == otherAction.expression && prior.body == otherAction.body:
                found = true
                break
            ..
        ..
        if not found:
            prior.conditional = true
            try target.onErrors.set(i, prior)
        ..
    ..
    for i := 0 to other.provenance.count():
        fact := try other.provenance.get(i)
        factIndex u64
        if not findPointerFact(target, fact.destination, addrof factIndex):
            try target.provenance.pushRight(ctx.alloc, fact)
        ..
    ..
..

mergeBranches(target Flow*, left Flow*, right Flow*) !void:
    if left.terminated:
        if right.terminated:
            target.terminated = true
            ret
        ..
        target.facts = move right.facts
        target.deferred = move right.deferred
        target.onErrors = move right.onErrors
        target.provenance = move right.provenance
        target.terminated = false
        ret
    ..
    target.facts = move left.facts
    target.deferred = move left.deferred
    target.onErrors = move left.onErrors
    target.provenance = move left.provenance
    target.terminated = false
    if not right.terminated:
        try mergeFlow(target, right)
    ..
..

mergeAlternative(target Flow*, other Flow*) !void:
    if target.terminated:
        if other.terminated:
            ret
        ..
        target.facts = move other.facts
        target.deferred = move other.deferred
        target.onErrors = move other.onErrors
        target.provenance = move other.provenance
        target.terminated = false
        ret
    ..
    if not other.terminated:
        try mergeFlow(target, other)
    ..
..

checkStatement(a Analyzer*, flow Flow*, statement nt.Stmt*) !void:
    if statement == none || flow.terminated:
        ret
    ..
    match statement as value:
    case nt.Stmt.Body:
        priorScope := a.scope
        if value.scope != none: a.scope = value.scope.id ..
        for i := 0 to value.statements.count():
            try checkStatement(a, flow, value.statements.get(i))
        ..
        if not flow.terminated && value.scope != none:
            try unwindScope(a, flow, value.scope.id, try statementPosition(statement))
        ..
        a.scope = priorScope
    case nt.Stmt.Expression:
        if isDiscardedOwner(value.expr):
            position := org.FilePos(line=0, column=0)
            match value.expr as discarded:
            case nt.Expr.DirectCall: position = discarded.sourcePos
            case nt.Expr.TemplatedDirectCall: position = discarded.sourcePos
            case nt.Expr.IndirectCall: position = discarded.sourcePos
            case nt.Expr.TemplatedIndirectCall: position = discarded.sourcePos
            else: position = position
            ..
            try diagnose(a, "OWNERSHIP_DISCARDED_RESULT", "owned result is discarded without being consumed", position, true)
        ..
        try readExpression(a, flow, value.expr, false)
    case nt.Stmt.Break:
        flow.terminated = true
    case nt.Stmt.Continue:
        flow.terminated = true
    case nt.Stmt.Defer:
        # Deferred calls run at scope exit. The legacy behavior is retained by
        # leaving them registered for the exit checker added below.
        try flow.deferred.pushRight(ctx.alloc, DeferAction(expression=value.expr, body=value.body, conditional=false, scope=a.scope))
    case nt.Stmt.OnError:
        try flow.onErrors.pushRight(ctx.alloc, ErrorAction(expression=value.expr, body=value.body, conditional=false, scope=a.scope))
    case nt.Stmt.Unsafe:
        if value.body != none: try checkStatement(a, flow, value.body) ..
        if value.expr != none: try readExpression(a, flow, value.expr, false) ..
    case nt.Stmt.Bounded:
        for i := 0 to value.predicates.count(): try readExpression(a, flow, value.predicates.get(i), false) ..
        for i := 0 to value.pointers.count():
            try readExpression(a, flow, value.pointers.get(i), false)
            try readExpression(a, flow, value.extents.get(i), false)
        ..
        try checkStatement(a, flow, value.body)
    case nt.Stmt.If:
        try readExpression(a, flow, value.condition, false)
        thenFlow := try cloneFlowFromPointer(flow)
        elseFlow := try cloneFlowFromPointer(flow)
        for i := 0 to thenFlow.facts.length:
            fact := try thenFlow.facts.get(i)
            if fact.conditional:
                predicate := predicateKind(value.condition, fact.condition)
                if predicate == 1: try refineConditional(addrof thenFlow, fact.condition, true) ..
                if predicate == 2: try refineConditional(addrof thenFlow, fact.condition, false) ..
                if predicate == 1: try refineConditional(addrof elseFlow, fact.condition, false) ..
                if predicate == 2: try refineConditional(addrof elseFlow, fact.condition, true) ..
            ..
        ..
        try checkStatement(a, addrof thenFlow, value.body)
        try checkStatement(a, addrof elseFlow, value.next)
        try mergeBranches(flow, addrof thenFlow, addrof elseFlow)
    case nt.Stmt.Elif:
        try readExpression(a, flow, value.condition, false)
        thenFlow := try cloneFlowFromPointer(flow)
        elseFlow := try cloneFlowFromPointer(flow)
        try checkStatement(a, addrof thenFlow, value.body)
        try checkStatement(a, addrof elseFlow, value.next)
        try mergeBranches(flow, addrof thenFlow, addrof elseFlow)
    case nt.Stmt.Else:
        try checkStatement(a, flow, value.body)
    case nt.Stmt.Loop:
        try readExpression(a, flow, value.condition, false)
        before := try cloneFlowFromPointer(flow)
        body := try cloneFlowFromPointer(flow)
        try checkStatement(a, addrof body, value.body)
        try mergeFlow(flow, addrof body)
        try mergeFlow(flow, addrof before)
    case nt.Stmt.ForLoop:
        try readExpression(a, flow, value.bound, false)
        before := try cloneFlowFromPointer(flow)
        body := try cloneFlowFromPointer(flow)
        try checkStatement(a, addrof body, value.body)
        try mergeFlow(flow, addrof body)
        try mergeFlow(flow, addrof before)
    case nt.Stmt.Match:
        try readExpression(a, flow, value.expression, false)
        merged := try cloneFlowFromPointer(flow)
        hasMergedBranch := value.elseBody == none
        allBranchesTerminated := value.elseBody != none
        for i := 0 to value.cases.count():
            branch := try cloneFlowFromPointer(flow)
            item := try value.cases.get(i)
            try checkStatement(a, addrof branch, item.body)
            if not branch.terminated: allBranchesTerminated = false ..
            if hasMergedBranch:
                try mergeAlternative(addrof merged, addrof branch)
            else:
                merged = move branch
                hasMergedBranch = true
            ..
        ..
        if value.elseBody != none:
            branch := try cloneFlowFromPointer(flow)
            try checkStatement(a, addrof branch, value.elseBody)
            if not branch.terminated: allBranchesTerminated = false ..
            if hasMergedBranch:
                try mergeAlternative(addrof merged, addrof branch)
            else:
                merged = move branch
                hasMergedBranch = true
            ..
        ..
        flow.facts = move merged.facts
        flow.deferred = move merged.deferred
        flow.onErrors = move merged.onErrors
        flow.provenance = move merged.provenance
        flow.terminated = allBranchesTerminated
    else:
        ret
    ..
..

typeDeclaration(value nt.Type*, depth u64) dclr.Decl*:
    if value == none || depth > 32: ret none ..
    match value as kind:
    case nt.Type.Named: ret kind.decl
    case nt.Type.Owned: ret typeDeclaration(kind.ofType, depth + 1)
    case nt.Type.Pointer: ret typeDeclaration(kind.toType, depth + 1)
    case nt.Type.Templated: ret typeDeclaration(kind.owner, depth + 1)
    case nt.Type.Throwing: ret typeDeclaration(kind.ofType, depth + 1)
    else: ret none
    ..
..

registerDestructor(a Analyzer*, declaration dclr.Decl*) !void:
    for i := 0 to a.destructorMethods.count():
        existing dclr.Decl*
        unsafe: existing = a.destructorMethods.data[i] ..
        if existing == declaration:
            ret
        ..
    ..
    try a.destructorMethods.pushRight(ctx.alloc, declaration)
    owner := typeDeclaration(declaration.methodOwnerType, 0)
    if owner != none:
        found := false
        for i := 0 to a.destructible.count():
            existing dclr.Decl*
            unsafe: existing = a.destructible.data[i] ..
            if existing == owner: found = true ..
        ..
        if not found: try a.destructible.pushRight(ctx.alloc, owner) ..
    ..
..

collectDestructors(a Analyzer*, root nt.Root*) !void:
    for i := 0 to root.statements.count():
        statement := try root.statements.get(i)
        match statement as value:
        case nt.GlobalStmt.Function:
            if value.header.decl != none:
                try collectPointerSummary(a, value.header.decl, value.header, value.body)
            ..
        case nt.GlobalStmt.Method:
            match value.methodBody as method:
            case nt.GlobalStmt.Function:
                if method.isDestructor && method.header.decl != none:
                    try registerDestructor(a, method.header.decl)
                ..
                if method.header.decl != none:
                    try collectPointerSummary(a, method.header.decl, method.header, method.body)
                ..
            else: continue
            ..
        else: continue
        ..
    ..
..

recordPointerReturn(a Analyzer*, summary PointerSummary*, header nt.Header*, expression nt.Expr*) !void:
    if expression == none:
        ret
    ..
    match expression as value:
    case nt.Expr.Move:
        try recordPointerReturn(a, summary, header, value.operand)
    case nt.Expr.Named:
        if header != none:
            for i := 0 to header.fields.count():
                field := try header.fields.get(i)
                match field as parameter:
                case nt.Expr.VarDef:
                    if parameter.decl == value.decl:
                        if summary.returnedParameter == none:
                            summary.returnedParameter = parameter.decl
                        elif summary.returnedParameter != parameter.decl:
                            summary.ambiguous = true
                        ..
                    ..
                else:
                    continue
                ..
            ..
        ..
    case nt.Expr.Unary:
        if value.op == tkt.KwType.ADDROF || value.op == tkt.KwType.AMPERSAND:
            source := placeRoot(value.operand)
            pointsIntoStack := false
            match value.operand as addressed:
            case nt.Expr.Named:
                pointsIntoStack = source != none && (try localStorage(source))
            case nt.Expr.MemberAccess:
                ownerType := expressionType(addressed.owner)
                match ownerType as ownerKind:
                case nt.Type.Pointer:
                    pointsIntoStack = false
                else:
                    pointsIntoStack = source != none && (try localStorage(source))
                ..
            case nt.Expr.Subscript:
                ownerType := expressionType(addressed.owner)
                match ownerType as ownerKind:
                case nt.Type.Pointer:
                    # Indexing through a pointer addresses its pointee, not the
                    # local stack slot that stores the pointer.
                    pointsIntoStack = false
                else:
                    pointsIntoStack = source != none && (try localStorage(source))
                ..
            else:
                pointsIntoStack = source != none && (try localStorage(source))
            ..
            if pointsIntoStack:
                summary.stackSource = source
                summary.returnsStackStorage = true
            ..
        ..
    else:
        ret
    ..
..

scanPointerReturns(a Analyzer*, summary PointerSummary*, header nt.Header*, statement nt.Stmt*) !void:
    if statement == none:
        ret
    ..
    match statement as value:
    case nt.Stmt.Body:
        for i := 0 to value.statements.count():
            try scanPointerReturns(a, summary, header, value.statements.get(i))
        ..
    case nt.Stmt.Expression:
        match value.expr as expression:
        case nt.Expr.Return: try recordPointerReturn(a, summary, header, expression.expr)
        else: ret
        ..
    case nt.Stmt.If:
        try scanPointerReturns(a, summary, header, value.body)
        try scanPointerReturns(a, summary, header, value.next)
    case nt.Stmt.Elif:
        try scanPointerReturns(a, summary, header, value.body)
        try scanPointerReturns(a, summary, header, value.next)
    case nt.Stmt.Else:
        try scanPointerReturns(a, summary, header, value.body)
    case nt.Stmt.Loop:
        try scanPointerReturns(a, summary, header, value.body)
    case nt.Stmt.ForLoop:
        try scanPointerReturns(a, summary, header, value.body)
    case nt.Stmt.Match:
        for i := 0 to value.cases.count():
            try scanPointerReturns(a, summary, header, (try value.cases.get(i)).body)
        ..
        try scanPointerReturns(a, summary, header, value.elseBody)
    case nt.Stmt.Bounded:
        try scanPointerReturns(a, summary, header, value.body)
    case nt.Stmt.Unsafe:
        try scanPointerReturns(a, summary, header, value.body)
    case nt.Stmt.OnError:
        try scanPointerReturns(a, summary, header, value.body)
    case nt.Stmt.Defer:
        try scanPointerReturns(a, summary, header, value.body)
    else:
        ret
    ..
..

collectPointerSummary(a Analyzer*, function dclr.Decl*, header nt.Header*, body nt.Stmt*) !void:
    if function == none || body == none:
        ret
    ..
    match function.kind as functionKind:
    case dclr.DeclKind.Function:
        if not pointerOrSlice(functionKind.returnType):
            ret
        ..
    else:
        ret
    ..
    summary := PointerSummary(function=function, returnedParameter=none, stackSource=none, returnsStackStorage=false, ambiguous=false)
    try scanPointerReturns(a, addrof summary, header, body)
    if summary.returnedParameter != none || summary.returnsStackStorage:
        try a.pointerSummaries.pushRight(ctx.alloc, summary)
    ..
..

checkFunction(a Analyzer*, header nt.Header*, body nt.Stmt*, returnType nt.Type*) !void:
    if body == none:
        ret
    ..
    flow := Flow(facts=emptyFacts(), deferred=nt.emptyNodeArray[DeferAction](), onErrors=nt.emptyNodeArray[ErrorAction](), provenance=nt.emptyNodeArray[PointerFact](), terminated=false)
    a.returnOwned = ownedResult(returnType, 0)
    if header != none:
        for i := 0 to header.fields.count():
            field := try header.fields.get(i)
            match field as argument:
            case nt.Expr.VarDef:
                if argument.decl != none && not isFieldDeclaration(argument.decl) && trackedType(a, argument.type, 0):
                    initialState := OwnerState.BORROWED
                    if isOwned(argument.type): initialState = OwnerState.LIVE ..
                    try addOwner(addrof flow, argument.decl, initialState, false, none)
                ..
            else:
                ret
            ..
        ..
    ..
    try checkStatement(a, addrof flow, body)
    if not flow.terminated:
        try checkExit(a, addrof flow, try statementPosition(body))
    ..
..

isTemplatedHeader(header nt.Header*) bool:
    if header == none: ret false ..
    match header.kind as kind:
    case nt.HeaderKind.Templated: ret true
    else: ret false
    ..
..

checkExit(a Analyzer*, flow Flow*, position org.FilePos) !void:
    deferredIndex := flow.deferred.count()
    loop deferredIndex > 0:
        deferredIndex = deferredIndex - 1
        action := try flow.deferred.get(deferredIndex)
        if action.conditional:
            actionFlow := try cloneFlowFromPointer(flow)
            if action.expression != none: try runCleanupExpression(a, addrof actionFlow, action.expression) ..
            if action.body != none: try checkStatement(a, addrof actionFlow, action.body) ..
            try mergeFlow(flow, addrof actionFlow)
        else:
            if action.expression != none: try runCleanupExpression(a, flow, action.expression) ..
            if action.body != none: try checkStatement(a, flow, action.body) ..
        ..
    ..
    for i := 0 to flow.facts.length:
        fact := try flow.facts.get(i)
        if fact.state == OwnerState.LIVE || fact.state == OwnerState.MAYBE_CONSUMED:
            try diagnoseRelated(a, "OWNERSHIP_LEAK", "owned value is not consumed on every exit path", fact.declaration.sourcePos, a.file, position, true)
        ..
    ..
..

checkThrowingFailure(a Analyzer*, input Flow*, position org.FilePos) !void:
    failure := try cloneFlowFromPointer(input)
    index := failure.onErrors.count()
    loop index > 0:
        index = index - 1
        action := try failure.onErrors.get(index)
        if action.conditional:
            handled := try cloneFlowFromPointer(addrof failure)
            if action.expression != none: try runCleanupExpression(a, addrof handled, action.expression) ..
            if action.body != none: try checkStatement(a, addrof handled, action.body) ..
            try mergeFlow(addrof failure, addrof handled)
        else:
            if action.expression != none: try runCleanupExpression(a, addrof failure, action.expression) ..
            if action.body != none: try checkStatement(a, addrof failure, action.body) ..
        ..
    ..
    try checkExit(a, addrof failure, position)
..

removeDeferred(flow Flow*, index u64) void:
    if index + 1 < flow.deferred.length:
        unsafe:
            for i := index to flow.deferred.length - 1:
                flow.deferred.data[i] = flow.deferred.data[i + 1]
            ..
        ..
    ..
    flow.deferred.length = flow.deferred.length - 1
..

removeErrorAction(flow Flow*, index u64) void:
    if index + 1 < flow.onErrors.length:
        unsafe:
            for i := index to flow.onErrors.length - 1:
                flow.onErrors.data[i] = flow.onErrors.data[i + 1]
            ..
        ..
    ..
    flow.onErrors.length = flow.onErrors.length - 1
..

removePointerFact(flow Flow*, index u64) void:
    if index + 1 < flow.provenance.length:
        unsafe:
            for i := index to flow.provenance.length - 1:
                flow.provenance.data[i] = flow.provenance.data[i + 1]
            ..
        ..
    ..
    flow.provenance.length = flow.provenance.length - 1
..

unwindScope(a Analyzer*, flow Flow*, scope u64, exitPosition org.FilePos) !void:
    index := flow.deferred.count()
    loop index > 0:
        index = index - 1
        action := try flow.deferred.get(index)
        if action.scope == scope:
            if action.conditional:
                actionFlow := try cloneFlowFromPointer(flow)
                if action.expression != none: try runCleanupExpression(a, addrof actionFlow, action.expression) ..
                if action.body != none: try checkStatement(a, addrof actionFlow, action.body) ..
                try mergeFlow(flow, addrof actionFlow)
            else:
                if action.expression != none: try runCleanupExpression(a, flow, action.expression) ..
                if action.body != none: try checkStatement(a, flow, action.body) ..
            ..
            removeDeferred(flow, index)
        ..
    ..
    index = flow.onErrors.count()
    loop index > 0:
        index = index - 1
        action := try flow.onErrors.get(index)
        if action.scope == scope: removeErrorAction(flow, index) ..
    ..
    index = flow.provenance.count()
    loop index > 0:
        index = index - 1
        fact := try flow.provenance.get(index)
        if fact.destination.owner.scope == scope: removePointerFact(flow, index) ..
    ..
    index = flow.facts.length
    loop index > 0:
        index = index - 1
        fact := try flow.facts.get(index)
        if fact.declaration.owner.scope == scope:
            if fact.state == OwnerState.LIVE || fact.state == OwnerState.MAYBE_CONSUMED:
                related fctx.FileCtx* = none
                if exitPosition.line != 0 || exitPosition.column != 0: related = a.file ..
                try diagnoseRelated(a, "OWNERSHIP_LEAK", "owned value is not consumed on every scope exit", fact.declaration.sourcePos, related, exitPosition, true)
            ..
            try flow.facts.remove(index)
        ..
    ..
..

checkRoot(a Analyzer*, root nt.Root*) !void:
    for i := 0 to root.statements.count():
        statement := try root.statements.get(i)
        match statement as value:
        case nt.GlobalStmt.Function:
            if not isTemplatedHeader(value.header):
                try checkFunction(a, value.header, value.body, value.retType)
            ..
        case nt.GlobalStmt.Method:
            match value.methodBody as method:
            case nt.GlobalStmt.Function:
                if not isTemplatedHeader(method.header):
                    try checkFunction(a, method.header, method.body, method.retType)
                ..
            else: continue
            ..
        else: continue
        ..
    ..
..

pub runGraph(files fctx.FileArray) !error:
    if files.count() == 0: ret errs.ok() ..
    first := try files.get(0)
    shared := Analyzer(
        file=first,
        destructible=dclr.emptyDeclArray(),
        destructorMethods=dclr.emptyDeclArray(),
        pointerSummaries=nt.emptyNodeArray[PointerSummary](),
        diagnostics=try ls.new[comperr.CompErr](ctx.alloc, none),
        hasErrors=false,
        scope=0,
        returnOwned=false,
        genericSpecialization=false,
    )
    # Pass one records which resolved types have destructor methods.
    for i := 0 to files.count():
        file := try files.get(i)
        shared.file = file
        try collectDestructors(addrof shared, addrof file.astRoot)
    ..
    # Pass two evaluates ownership flow. Branches clone and join the compact
    # fact set; loops conservatively join the zero-iteration and body paths.
    for i := 0 to files.count():
        file := try files.get(i)
        shared.file = file
        try checkRoot(addrof shared, addrof file.astRoot)
        for j := 0 to file.specializations.count():
            specialization := try file.specializations.get(j)
            if specialization.isFunction:
                specializationFile := try gl.files.get(specialization.template.module.path)
                shared.file = specializationFile
                returnType nt.Type* = none
                match specialization.template.kind as templateKind:
                case dclr.DeclKind.Function:
                    returnType = templateKind.returnType
                else:
                    returnType = none
                ..
                shared.genericSpecialization = true
                try checkFunction(addrof shared, specialization.concreteHeader, specialization.concreteBody, returnType)
                shared.genericSpecialization = false
                shared.file = file
            ..
        ..
    ..
    for i := 0 to shared.diagnostics.count():
        diagnostic := try shared.diagnostics.get(i)
        diagnostic.log()
    ..
    if shared.hasErrors: ret errs.failure("ownership safety checking failed") ..
    ret errs.ok()
..

