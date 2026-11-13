mod node_types

use "std:allocator" alc
use "std:checked" checked
use "std:errors" errors
use "std:footgun" fg

# Append-only storage for variable-length AST fields. It is allocation-free
# until the first append, then grows from four slots by doubling.
pub NodeArray[T](
    data T*
    length u64
    capacity u64
)

pub emptyNodeArray[T]() NodeArray[T]:
    ret NodeArray[T](data=none, length=0, capacity=0)
..

pub NodeArray[T].count() u64:
    ret this.length
..

pub NodeArray[T].get(index u64) !T:
    if index >= this.length:
        throw errors.outOfBounds("node array index is out of bounds")
    ..
    unsafe:
        ret this.data[index]
    ..
..

pub NodeArray[T].set(index u64, value T) !void:
    if index >= this.length:
        throw errors.outOfBounds("node array index is out of bounds")
    ..
    unsafe:
        this.data[index] = value
    ..
..

pub NodeArray[T].pushRight(a alc.Allocator, value T) !void:
    newLength := try checked.uAdd(this.length, 1)
    if this.length == this.capacity:
        newCapacity u64 = 4
        if this.capacity != 0:
            newCapacity = try checked.uMul(this.capacity, 2)
        ..
        if this.data == none:
            this.data = try a.allocT[T](newCapacity)
        else:
            this.data = try a.reallocT[T](this.data, newCapacity)
        ..
        this.capacity = newCapacity
    ..
    unsafe:
        this.data[this.length] = value
    ..
    this.length = newLength
..

# Variable-length AST fields use NodeArray so empty fields need no allocation.

pub proto Node()

pub Root impl Node(
    statements NodeArray[GlobalStmt*]
)

pub union HeaderKind(
    Plain()
    Templated(typeArgs NodeArray[Type*])
)

pub Header impl Node(
    id u64
    scopeId u64
    name str
    fields NodeArray[Expr*]
    kind HeaderKind
)

pub union Name impl Node(
    Simple(name str)
    Composite(names NodeArray[str])
)

pub MatchCase impl Node(
    variant Name*
    body Stmt*
)

pub ProtoMethod impl Node(
    id u64
    header Header*
    returnType Type*
    noContext bool
)

pub union Type impl Node(
    Named(name Name*, id u64)
    Pointer(toType Type*)
    Templated(owner Type*, args NodeArray[Type*])
    Slice(ofType Type*)
    Owned(ofType Type*)
    Throwing(ofType Type*)
    Function(args NodeArray[Type*], returnType Type*, noContext bool)
    CompilerKnown(name str)
)

pub union Stmt impl Node(
    Body(statements NodeArray[Stmt*], scopeId u64)
    Expression(expr Expr*)
    Break()
    Continue()
    Defer(expr Expr*, body Stmt*)
    OnError(expr Expr*, body Stmt*)
    Unsafe(expr Expr*, body Stmt*)
    Bounded(predicates NodeArray[Expr*], pointers NodeArray[Expr*], extents NodeArray[Expr*], body Stmt*)
    Match(expression Expr*, binding str, bindingDeclId u64, cases NodeArray[MatchCase*], elseBody Stmt*)
    LLVM(text str)
    If(condition Expr*, body Stmt*, next Stmt*)
    Elif(condition Expr*, body Stmt*, next Stmt*)
    Else(body Stmt*)
    Loop(condition Expr*, body Stmt*)
    ForLoop(index Expr*, bound Expr*, body Stmt*, scopeId u64)
)

pub union GlobalStmt impl Node(
    Struct(header Header*, implements NodeArray[Type*], isPublic bool)
    Function(header Header*, retType Type*, body Stmt*, isPublic bool, noContext bool, isDestructor bool)
    ExternalFunction(header Header*, externalName str, retType Type*, isPublic bool, noContext bool)
    Variable(id u64, name str, type Type*, initializer Expr*, isPublic bool, isGlobal bool, isConst bool)
    Alias(id u64, name Name*, type Type*, isPublic bool)
    Method(ownerType Type*, name Name*, methodBody GlobalStmt*)
    Union(id u64, name str, scopeId u64, implements NodeArray[Type*], variants NodeArray[Header*], isPublic bool)
    Enum(id u64, name str, scopeId u64, backing Type*, variants NodeArray[Expr*], isPublic bool)
    Proto(id u64, name str, scopeId u64, implements NodeArray[Type*], methods NodeArray[ProtoMethod*], isPublic bool)
    LLVM(text str)
    Embed()
)

pub union Literal impl Node(
    None()
    String(value str)
    Number(value str)
    HexNumber(value str)
    Boolean(value bool)
    Char8(value str)
    Char32(value str)
)

pub union Expr impl Node(
    Empty()
    Literal(type Type*, literal Literal*)
    Named(type Type*, name str, declId u64)
    MemberAccess(type Type*, owner Expr*, member Expr*)
    Subscript(type Type*, owner Expr*, index Expr*)
    Array(type Type*, length Expr*, inferLength bool)
    Embed(path str)
    CompilerKnown(name str)
    InlineLLVM(operation str)
    VarDef(type Type*, name str, declId u64, boundedCount str)
    VarDefAssign(type Type*, name str, assignment Expr*, declId u64)
    VarDefAssignDestructure(type Type*, nameValue str, nameError str, call Expr*, valueDeclId u64, errorDeclId u64)
    Sizeof(type Type*, operand Type*)
    Unary(type Type*, op u8, operand Expr*)
    Move(operand Expr*)
    Binary(type Type*, op u8, left Expr*, right Expr*)
    DirectCall(type Type*, declId u64, args NodeArray[Expr*])
    TemplatedDirectCall(type Type*, declId u64, args NodeArray[Expr*], typeArgs NodeArray[Type*])
    IndirectCall(type Type*, owner Expr*, args NodeArray[Expr*])
    TemplatedIndirectCall(type Type*, owner Expr*, args NodeArray[Expr*], typeArgs NodeArray[Type*])
    GenericApply(owner Expr*, typeArgs NodeArray[Type*])
    Try(type Type*, call Expr*)
    Assign(type Type*, assignee Expr*, expr Expr*)
    Return(expr Expr*)
    Throw(expr Expr*)
)


