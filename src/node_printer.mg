mod node_printer

use "std:fmt" fmt
use "std:array" arr
use "std:io" io
use "shared/node_types" nt
use "shared/global" gl
use "helper/logger" log

writeIndent(level u64) !void:
    stdout := io.stdoutConst()
    writer := stdout.toWriter()
    for i := 0 to level:
        try writer.write("  ")
    ..
..

writeLine(level u64, text str) !void:
    stdout := io.stdoutConst()
    writer := stdout.toWriter()
    try writeIndent(level)
    try writer.write(text)
    try writer.write("\n")
..

writeNamedLine(level u64, label str, name str) !void:
    stdout := io.stdoutConst()
    writer := stdout.toWriter()
    try writeIndent(level)
    try fmt.str(ctx.alloc, label).str(name).str("\n").writeTo(writer)
..

writeIdLine(level u64, label str, id u64) !void:
    stdout := io.stdoutConst()
    writer := stdout.toWriter()
    try writeIndent(level)
    try fmt.str(ctx.alloc, label).uint(id).str("\n").writeTo(writer)
..

writeNamedIdLine(level u64, label str, name str, id u64) !void:
    stdout := io.stdoutConst()
    writer := stdout.toWriter()
    try writeIndent(level)
    try fmt.str(ctx.alloc, label).str(name).str(" #").uint(id).str("\n").writeTo(writer)
..

pub printRoot(root nt.Root*) !void:
    w := try gl.startLog(log.LogLevel.VERBOSE)
    defer w.end()

    try writeLine(0, "AST")
    statementCount := root.statements.count()
    for i := 0 to statementCount:
        statement := try root.statements.get(i)
        try printGlobal(statement, 1)
    ..
..

printName(name nt.Name*, level u64) !void:
    if name == none:
        try writeLine(level, "Name <none>")
        ret
    ..
    local nt.Name
    unsafe local = *name
    match local as value:
    case nt.Name.Simple:
        try writeNamedLine(level, "Name.Simple ", value.name)
    case nt.Name.Composite:
        try writeLine(level, "Name.Composite")
        for i := 0 to value.names.count():
            part := try value.names.get(i)
            try writeNamedLine(level + 1, "Part ", part)
        ..
    ..
..

printHeader(header nt.Header*, level u64) !void:
    if header == none:
        try writeLine(level, "Header <none>")
        ret
    ..
    try writeNamedIdLine(level, "Header ", header.name, header.id)
    try writeIdLine(level + 1, "Scope ", header.scopeId)
    try writeLine(level + 1, "Type arguments")
    kind := header.kind
    match kind as template:
    case nt.HeaderKind.Templated:
        for i := 0 to template.typeArgs.count():
            value := try template.typeArgs.get(i)
            try printType(value, level + 2)
        ..
    case nt.HeaderKind.Plain:
        try writeLine(level + 2, "<none>")
    ..
    try writeLine(level + 1, "Fields")
    for i := 0 to header.fields.count():
        value := try header.fields.get(i)
        try printExpr(value, level + 2)
    ..
..

printType(type nt.Type*, level u64) !void:
    if type == none:
        try writeLine(level, "Type <inferred>")
        ret
    ..
    local nt.Type
    unsafe local = *type
    match local as value:
    case nt.Type.Named:
        try writeIdLine(level, "Type.Named #", value.id)
        try printName(value.name, level + 1)
    case nt.Type.Pointer:
        try writeLine(level, "Type.Pointer")
        try printType(value.toType, level + 1)
    case nt.Type.Templated:
        try writeLine(level, "Type.Templated")
        try printType(value.owner, level + 1)
        for i := 0 to value.args.count():
            arg := try value.args.get(i)
            try printType(arg, level + 1)
        ..
    case nt.Type.Slice:
        try writeLine(level, "Type.Slice")
        try printType(value.ofType, level + 1)
    case nt.Type.Owned:
        try writeLine(level, "Type.Owned")
        try printType(value.ofType, level + 1)
    case nt.Type.Throwing:
        try writeLine(level, "Type.Throwing")
        try printType(value.ofType, level + 1)
    case nt.Type.Function:
        try writeLine(level, "Type.Function")
        try writeLine(level + 1, "Arguments")
        for i := 0 to value.args.count():
            arg := try value.args.get(i)
            try printType(arg, level + 2)
        ..
        try writeLine(level + 1, "Return type")
        try printType(value.returnType, level + 2)
    case nt.Type.CompilerKnown:
        try writeNamedLine(level, "Type.CompilerKnown ", value.name)
    ..
..

printGlobal(statement nt.GlobalStmt*, level u64) !void:
    if statement == none:
        try writeLine(level, "Global <none>")
        ret
    ..
    local nt.GlobalStmt
    unsafe local = *statement
    match local as value:
    case nt.GlobalStmt.Struct:
        try writeLine(level, "Global.Struct")
        try printHeader(value.header, level + 1)
    case nt.GlobalStmt.Function:
        try writeLine(level, "Global.Function")
        try printHeader(value.header, level + 1)
        try writeLine(level + 1, "Return type")
        try printType(value.retType, level + 2)
        try printStmt(value.body, level + 1)
    case nt.GlobalStmt.ExternalFunction:
        try writeLine(level, "Global.ExternalFunction")
        try writeNamedLine(level + 1, "External name ", value.externalName)
        try printHeader(value.header, level + 1)
        try printType(value.retType, level + 1)
    case nt.GlobalStmt.Variable:
        try writeNamedIdLine(level, "Global.Variable ", value.name, value.id)
        try printType(value.type, level + 1)
        try printExpr(value.initializer, level + 1)
    case nt.GlobalStmt.Alias:
        try writeNamedIdLine(level, "Global.Alias ", "", value.id)
        try printName(value.name, level + 1)
        try printType(value.type, level + 1)
    case nt.GlobalStmt.Method:
        try writeLine(level, "Global.Method")
        try printType(value.ownerType, level + 1)
        try printName(value.name, level + 1)
        try printGlobal(value.methodBody, level + 1)
    case nt.GlobalStmt.Union:
        try writeNamedIdLine(level, "Global.Union ", value.name, value.id)
        try writeIdLine(level + 1, "Scope ", value.scopeId)
        for i := 0 to value.implements.count():
            implemented := try value.implements.get(i)
            try writeLine(level + 1, "Implements")
            try printType(implemented, level + 2)
        ..
        for i := 0 to value.variants.count():
            variant := try value.variants.get(i)
            try printHeader(variant, level + 1)
        ..
    case nt.GlobalStmt.Enum:
        try writeNamedIdLine(level, "Global.Enum ", value.name, value.id)
        try writeIdLine(level + 1, "Scope ", value.scopeId)
        try printType(value.backing, level + 1)
        for i := 0 to value.variants.count():
            variant := try value.variants.get(i)
            try printExpr(variant, level + 1)
        ..
    case nt.GlobalStmt.Proto:
        try writeNamedIdLine(level, "Global.Proto ", value.name, value.id)
        try writeIdLine(level + 1, "Scope ", value.scopeId)
        for i := 0 to value.implements.count():
            implemented := try value.implements.get(i)
            try writeLine(level + 1, "Implements")
            try printType(implemented, level + 2)
        ..
        for i := 0 to value.methods.count():
            method := try value.methods.get(i)
            try writeNamedIdLine(level + 1, "ProtoMethod ", method.header.name, method.id)
            try printHeader(method.header, level + 2)
            try printType(method.returnType, level + 2)
        ..
    case nt.GlobalStmt.LLVM:
        try writeNamedLine(level, "Global.LLVM ", value.text)
    case nt.GlobalStmt.Embed:
        try writeLine(level, "Global.Embed")
    ..
..

printStmt(statement nt.Stmt*, level u64) !void:
    if statement == none:
        try writeLine(level, "Statement <none>")
        ret
    ..
    local nt.Stmt
    unsafe local = *statement
    match local as value:
    case nt.Stmt.Body:
        try writeIdLine(level, "Statement.Body scope #", value.scopeId)
        for i := 0 to value.statements.count():
            child := try value.statements.get(i)
            try printStmt(child, level + 1)
        ..
    case nt.Stmt.Expression:
        try writeLine(level, "Statement.Expression")
        try printExpr(value.expr, level + 1)
    case nt.Stmt.Break:
        try writeLine(level, "Statement.Break")
    case nt.Stmt.Continue:
        try writeLine(level, "Statement.Continue")
    case nt.Stmt.Defer:
        try writeLine(level, "Statement.Defer")
        try printExpr(value.expr, level + 1)
        try printStmt(value.body, level + 1)
    case nt.Stmt.OnError:
        try writeLine(level, "Statement.OnError")
        try printExpr(value.expr, level + 1)
        try printStmt(value.body, level + 1)
    case nt.Stmt.Unsafe:
        try writeLine(level, "Statement.Unsafe")
        try printExpr(value.expr, level + 1)
        try printStmt(value.body, level + 1)
    case nt.Stmt.Bounded:
        try writeLine(level, "Statement.Bounded")
        for i := 0 to value.predicates.count():
            predicate := try value.predicates.get(i)
            try writeLine(level + 1, "Predicate")
            try printExpr(predicate, level + 2)
        ..
        for i := 0 to value.pointers.count():
            pointer := try value.pointers.get(i)
            try writeLine(level + 1, "Pointer")
            try printExpr(pointer, level + 2)
            extent := try value.extents.get(i)
            try writeLine(level + 1, "Extent")
            try printExpr(extent, level + 2)
        ..
        try printStmt(value.body, level + 1)
    case nt.Stmt.Match:
        try writeNamedLine(level, "Statement.Match binding ", value.binding)
        try writeIdLine(level + 1, "Binding declaration #", value.bindingDeclId)
        try printExpr(value.expression, level + 1)
        for i := 0 to value.cases.count():
            item := try value.cases.get(i)
            try writeLine(level + 1, "Case")
            try printName(item.variant, level + 2)
            try printStmt(item.body, level + 2)
        ..
        try printStmt(value.elseBody, level + 1)
    case nt.Stmt.LLVM:
        try writeNamedLine(level, "Statement.LLVM ", value.text)
    case nt.Stmt.If:
        try writeLine(level, "Statement.If")
        try printExpr(value.condition, level + 1)
        try printStmt(value.body, level + 1)
        try printStmt(value.next, level + 1)
    case nt.Stmt.Elif:
        try writeLine(level, "Statement.Elif")
        try printExpr(value.condition, level + 1)
        try printStmt(value.body, level + 1)
        try printStmt(value.next, level + 1)
    case nt.Stmt.Else:
        try writeLine(level, "Statement.Else")
        try printStmt(value.body, level + 1)
    case nt.Stmt.Loop:
        try writeLine(level, "Statement.Loop")
        try printExpr(value.condition, level + 1)
        try printStmt(value.body, level + 1)
    case nt.Stmt.ForLoop:
        try writeIdLine(level, "Statement.ForLoop scope #", value.scopeId)
        try printExpr(value.index, level + 1)
        try writeLine(level + 1, "Bound")
        try printExpr(value.bound, level + 2)
        try printStmt(value.body, level + 1)
    ..
..

printExpr(expression nt.Expr*, level u64) !void:
    if expression == none:
        try writeLine(level, "Expression <none>")
        ret
    ..
    local nt.Expr
    unsafe local = *expression
    match local as value:
    case nt.Expr.Empty:
        try writeLine(level, "Expression.Empty")
    case nt.Expr.Literal:
        try writeLine(level, "Expression.Literal")
        try printType(value.type, level + 1)
        try printLiteral(value.literal, level + 1)
    case nt.Expr.Named:
        try writeNamedIdLine(level, "Expression.Named ", value.name, value.declId)
        try printType(value.type, level + 1)
    case nt.Expr.MemberAccess:
        try writeLine(level, "Expression.MemberAccess")
        try printExpr(value.owner, level + 1)
        try printExpr(value.member, level + 1)
    case nt.Expr.Subscript:
        try writeLine(level, "Expression.Subscript")
        try printExpr(value.owner, level + 1)
        try printExpr(value.index, level + 1)
    case nt.Expr.Array:
        try writeLine(level, "Expression.Array")
        try printType(value.type, level + 1)
        if value.inferLength:
            try writeLine(level + 1, "Length <inferred>")
        else:
            try printExpr(value.length, level + 1)
        ..
    case nt.Expr.Embed:
        try writeNamedLine(level, "Expression.Embed ", value.path)
    case nt.Expr.CompilerKnown:
        try writeNamedLine(level, "Expression.CompilerKnown ", value.name)
    case nt.Expr.InlineLLVM:
        try writeNamedLine(level, "Expression.InlineLLVM ", value.operation)
    case nt.Expr.VarDef:
        try writeNamedIdLine(level, "Expression.VarDef ", value.name, value.declId)
        try printType(value.type, level + 1)
    case nt.Expr.VarDefAssign:
        try writeNamedIdLine(level, "Expression.VarDefAssign ", value.name, value.declId)
        try printType(value.type, level + 1)
        try printExpr(value.assignment, level + 1)
    case nt.Expr.VarDefAssignDestructure:
        try writeLine(level, "Expression.VarDefAssignDestructure")
        try writeNamedIdLine(level + 1, "Value ", value.nameValue, value.valueDeclId)
        try writeNamedIdLine(level + 1, "Error ", value.nameError, value.errorDeclId)
        try printType(value.type, level + 1)
        try printExpr(value.call, level + 1)
    case nt.Expr.Unary:
        try writeIdLine(level, "Expression.Unary op ", value.op)
        try printType(value.type, level + 1)
        try printExpr(value.operand, level + 1)
    case nt.Expr.Sizeof:
        try writeLine(level, "Expression.Sizeof")
        try printType(value.type, level + 1)
        try printType(value.operand, level + 1)
    case nt.Expr.Move:
        try writeLine(level, "Expression.Move")
        try printExpr(value.operand, level + 1)
    case nt.Expr.Binary:
        try writeIdLine(level, "Expression.Binary op ", value.op)
        try printType(value.type, level + 1)
        try printExpr(value.left, level + 1)
        try printExpr(value.right, level + 1)
    case nt.Expr.DirectCall:
        try writeIdLine(level, "Expression.DirectCall declaration #", value.declId)
        try printType(value.type, level + 1)
        try printExprArray(value.args, "Arguments", level + 1)
    case nt.Expr.TemplatedDirectCall:
        try writeIdLine(level, "Expression.TemplatedDirectCall declaration #", value.declId)
        try printType(value.type, level + 1)
        try printExprArray(value.args, "Arguments", level + 1)
        try printTypeArray(value.typeArgs, "Type arguments", level + 1)
    case nt.Expr.IndirectCall:
        try writeLine(level, "Expression.IndirectCall")
        try printType(value.type, level + 1)
        try printExpr(value.owner, level + 1)
        try printExprArray(value.args, "Arguments", level + 1)
    case nt.Expr.TemplatedIndirectCall:
        try writeLine(level, "Expression.TemplatedIndirectCall")
        try printType(value.type, level + 1)
        try printExpr(value.owner, level + 1)
        try printExprArray(value.args, "Arguments", level + 1)
        try printTypeArray(value.typeArgs, "Type arguments", level + 1)
    case nt.Expr.GenericApply:
        try writeLine(level, "Expression.GenericApply")
        try printExpr(value.owner, level + 1)
        try printTypeArray(value.typeArgs, "Type arguments", level + 1)
    case nt.Expr.Try:
        try writeLine(level, "Expression.Try")
        try printType(value.type, level + 1)
        try printExpr(value.call, level + 1)
    case nt.Expr.Assign:
        try writeLine(level, "Expression.Assign")
        try printType(value.type, level + 1)
        try printExpr(value.assignee, level + 1)
        try printExpr(value.expr, level + 1)
    case nt.Expr.Return:
        try writeLine(level, "Expression.Return")
        try printExpr(value.expr, level + 1)
    case nt.Expr.Throw:
        try writeLine(level, "Expression.Throw")
        try printExpr(value.expr, level + 1)
    ..
..

printExprArray(values nt.NodeArray[nt.Expr*], label str, level u64) !void:
    try writeLine(level, label)
    for i := 0 to values.count():
        value := try values.get(i)
        try printExpr(value, level + 1)
    ..
..

printTypeArray(values nt.NodeArray[nt.Type*], label str, level u64) !void:
    try writeLine(level, label)
    for i := 0 to values.count():
        value := try values.get(i)
        try printType(value, level + 1)
    ..
..

printLiteral(literal nt.Literal*, level u64) !void:
    if literal == none:
        try writeLine(level, "Literal <none>")
        ret
    ..
    local nt.Literal
    unsafe local = *literal
    match local as value:
    case nt.Literal.None:
        try writeLine(level, "Literal.None")
    case nt.Literal.String:
        try writeNamedLine(level, "Literal.String ", value.value)
    case nt.Literal.Number:
        try writeNamedLine(level, "Literal.Number ", value.value)
    case nt.Literal.HexNumber:
        try writeNamedLine(level, "Literal.HexNumber ", value.value)
    case nt.Literal.Boolean:
        stdout := io.stdoutConst()
        writer := stdout.toWriter()
        try writeIndent(level)
        try fmt.str(ctx.alloc, "Literal.Boolean ").bool(value.value).str("\n").writeTo(writer)
    case nt.Literal.Char8:
        try writeNamedLine(level, "Literal.Char8 ", value.value)
    case nt.Literal.Char32:
        try writeNamedLine(level, "Literal.Char32 ", value.value)
    ..
..
