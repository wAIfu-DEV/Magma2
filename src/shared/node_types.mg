mod node_types

# Different node types making up the AST
# @author devan
# @author codex (GPT6 Luna)

use "origin" origin

use "std:allocator" alc
use "std:checked" checked
use "std:errors" errors
use "std:footgun" fg

use "../decl_resolver" declr

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

pub emptyTypeArray() NodeArray[Type*]:
    ret emptyNodeArray[Type*]()
..

pub emptyStringArray() NodeArray[str]:
    ret emptyNodeArray[str]()
..

pub emptyIndexArray() NodeArray[u64]:
    ret emptyNodeArray[u64]()
..

pub emptyExpressionArray() NodeArray[Expr*]:
    ret emptyNodeArray[Expr*]()
..

pub emptyStatementArray() NodeArray[Stmt*]:
    ret emptyNodeArray[Stmt*]()
..

pub emptyMatchCaseArray() NodeArray[MatchCase*]:
    ret emptyNodeArray[MatchCase*]()
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

# Concrete pointer arrays avoid recursive generic instantiations when semantic
# state must retain Type or Specialization pointers across checker calls.
pub TypePointerArray(
    data Type**
    length u64
    capacity u64
)

pub emptyTypePointerArray() TypePointerArray:
    ret TypePointerArray(data=none, length=0, capacity=0)
..

pub TypePointerArray.count() u64:
    ret this.length
..

pub TypePointerArray.get(index u64) !Type*:
    if index >= this.length:
        throw "type pointer array index is out of bounds"
    ..
    unsafe:
        ret this.data[index]
    ..
..

pub TypePointerArray.reserve(a alc.Allocator, capacity u64) !void:
    if capacity <= this.capacity:
        ret
    ..
    if this.data == none:
        this.data = try a.allocT[Type*](capacity)
    else:
        this.data = try a.reallocT[Type*](this.data, capacity)
    ..
    this.capacity = capacity
..

pub TypePointerArray.pushRight(a alc.Allocator, value Type*) !void:
    newLength := this.length + 1
    if this.length == this.capacity:
        newCapacity u64 = 4
        if this.capacity != 0:
            newCapacity = this.capacity * 2
        ..
        if this.data == none:
            this.data = try a.allocT[Type*](newCapacity)
        else:
            this.data = try a.reallocT[Type*](this.data, newCapacity)
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
    decl declr.Decl*
    scope declr.Scope*
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
    decl declr.Decl*
    body Stmt*
)

pub ProtoMethod impl Node(
    decl declr.Decl*
    header Header*
    returnType Type*
    noContext bool
)

pub union Type impl Node(
    Named(name Name*, decl declr.Decl*, primitive PrimitiveType)
    Pointer(toType Type*)
    Templated(owner Type*, args NodeArray[Type*])
    Slice(ofType Type*)
    Owned(ofType Type*)
    Throwing(ofType Type*)
    Function(args NodeArray[Type*], returnType Type*, noContext bool)
    CompilerKnown(name str, resolvedValue str)
    Void(x u8)
)


pub union Stmt impl Node(
    Body(statements NodeArray[Stmt*], scope declr.Scope*)
    Expression(expr Expr*)
    Break()
    Continue()
    Defer(expr Expr*, body Stmt*)
    OnError(expr Expr*, body Stmt*)
    Unsafe(expr Expr*, body Stmt*)
    Bounded(predicates NodeArray[Expr*], pointers NodeArray[Expr*], extents NodeArray[Expr*], body Stmt*)
    Match(expression Expr*, binding str, bindingDecl declr.Decl*, cases NodeArray[MatchCase*], elseBody Stmt*, pointerMode bool)
    LLVM(text str)
    If(condition Expr*, body Stmt*, next Stmt*, sourcePos origin.FilePos)
    Elif(condition Expr*, body Stmt*, next Stmt*, sourcePos origin.FilePos)
    Else(body Stmt*)
    Loop(condition Expr*, body Stmt*, sourcePos origin.FilePos)
    ForLoop(index Expr*, bound Expr*, body Stmt*, scope declr.Scope*)
)

pub union GlobalStmt impl Node(
    Struct(header Header*, implements NodeArray[Type*], isPublic bool)
    Function(header Header*, retType Type*, body Stmt*, isPublic bool, noContext bool, isDestructor bool)
    ExternalFunction(header Header*, externalName str, retType Type*, isPublic bool, noContext bool)
    Variable(id u64, name str, type Type*, initializer Expr*, isPublic bool, isGlobal bool, isConst bool)
    Alias(id u64, name Name*, type Type*, isPublic bool)
    Method(ownerType Type*, name Name*, methodBody GlobalStmt*)
    Union(id u64, name str, scope declr.Scope*, implements NodeArray[Type*], variants NodeArray[Header*], isPublic bool)
    Enum(id u64, name str, scope declr.Scope*, backing Type*, variants NodeArray[Expr*], isPublic bool)
    Proto(id u64, name str, scope declr.Scope*, implements NodeArray[Type*], methods NodeArray[ProtoMethod*], isPublic bool)
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

pub enum ValueCategory u8(
    Unresolved,
    Value,
    Place,
)

pub enum PrimitiveType u8(
    Unresolved,
    Pointer,
    Void,
    Bool,
    I8,
    I16,
    I32,
    I64,
    I128,
    U8,
    U16,
    U32,
    U64,
    U128,
    F16,
    F32,
    F64,
    F128,
    String,
    Error,
    Slice,
    None,
)

pub enum CallKind u8(
    Unresolved,
    Indirect,
    ArrayConstructor,
    StaticMethod,
    ProtoMethod,
    ProtoView,
    ProtoViewBorrow,
    ProtoImpl,
    ProtoImplBorrow,
    FunctionCall,
    StructConstructor,
    UnionConstructor,
)

pub union Expr impl Node(
    Empty()
    Literal(type Type*, literal Literal*)
    Zero(type Type*, sourcePos origin.FilePos)
    Named(type Type*, name str, decl declr.Decl*, category ValueCategory, sourcePos origin.FilePos)
    EnumVariant(type Type*, name str, decl declr.Decl*, sourcePos origin.FilePos)
    InferredStructConstructor(type Type*, decl declr.Decl*, args NodeArray[Expr*], sourcePos origin.FilePos)
    MemberAccess(type Type*, owner Expr*, member Expr*, category ValueCategory, isProtoMethod bool)
    Subscript(type Type*, owner Expr*, index Expr*, category ValueCategory, genericReference bool, genericTypeArg Type*)
    Array(type Type*, length Expr*, inferLength bool, resolvedLength u64, hasResolvedLength bool, resolvedIndices NodeArray[u64])
    Embed(path str)
    CompilerKnown(name str, resolvedValue str)
    InlineLLVM(type Type*, operation str, args NodeArray[Expr*])
    VarDef(type Type*, name str, decl declr.Decl*, boundedCount str, sourcePos origin.FilePos)
    VarDefAssign(type Type*, name str, assignment Expr*, decl declr.Decl*, sourcePos origin.FilePos)
    VarDefAssignDestructure(type Type*, nameValue str, nameError str, call Expr*, valueDecl declr.Decl*, errorDecl declr.Decl*)
    Sizeof(type Type*, operand Type*)
    Unary(type Type*, op u8, operand Expr*, category ValueCategory, floatingPoint bool)
    Move(type Type*, operand Expr*)
    Binary(type Type*, op u8, left Expr*, right Expr*, protoEquality bool, stringEquality bool, floatingPoint bool, unsignedOperation bool)
    DirectCall(type Type*, decl declr.Decl*, args NodeArray[Expr*], typeArgs NodeArray[Type*], sourcePos origin.FilePos, callKind CallKind)
    TemplatedDirectCall(type Type*, decl declr.Decl*, args NodeArray[Expr*], typeArgs NodeArray[Type*], sourcePos origin.FilePos, callKind CallKind)
    IndirectCall(type Type*, owner Expr*, args NodeArray[Expr*], typeArgs NodeArray[Type*], sourcePos origin.FilePos, callKind CallKind, target declr.Decl*)
    TemplatedIndirectCall(type Type*, owner Expr*, args NodeArray[Expr*], typeArgs NodeArray[Type*], sourcePos origin.FilePos, callKind CallKind, target declr.Decl*)
    GenericApply(type Type*, owner Expr*, typeArgs NodeArray[Type*])
    Try(type Type*, call Expr*)
    Assign(type Type*, assignee Expr*, expr Expr*, sourcePos origin.FilePos, resolvedFieldIndex u64, hasResolvedFieldIndex bool)
    Return(expr Expr*, sourcePos origin.FilePos)
    Throw(expr Expr*, sourcePos origin.FilePos)
)

# A concrete generic use discovered by semantic checking. The template's
# module owns this record so later compiler stages can find the instance.
pub Specialization impl Node(
    template declr.Decl*
    typeArgs NodeArray[Type*]
    typeParams declr.DeclArray
    concreteType Type*
    concreteHeader Header*
    concreteBody Stmt*
    isFunction bool
    state u8
)

pub SpecializationPointerArray(
    data Specialization**
    length u64
    capacity u64
)

pub emptySpecializationArray() SpecializationPointerArray:
    ret SpecializationPointerArray(data=none, length=0, capacity=0)
..

pub SpecializationPointerArray.count() u64:
    ret this.length
..

pub SpecializationPointerArray.get(index u64) !Specialization*:
    if index >= this.length:
        throw "specialization array index is out of bounds"
    ..
    unsafe:
        ret this.data[index]
    ..
..

pub SpecializationPointerArray.pushRight(a alc.Allocator, value Specialization*) !void:
    newLength := this.length + 1
    if this.length == this.capacity:
        newCapacity u64 = 4
        if this.capacity != 0:
            newCapacity = this.capacity * 2
        ..
        if this.data == none:
            this.data = try a.allocT[Specialization*](newCapacity)
        else:
            this.data = try a.reallocT[Specialization*](this.data, newCapacity)
        ..
        this.capacity = newCapacity
    ..
    unsafe:
        this.data[this.length] = value
    ..
    this.length = newLength
..

# Parsed AST nodes live in the stable AST arena for the lifetime of a file.
# These helpers make the intentional unsafe read/copy operations explicit to
# the semantic checker without asking the parser or checker to rebuild nodes.
pub loadNameNode(value Name*) Name:
    local Name
    unsafe:
        local = *value
    ..
    ret local
..

pub loadTypeNode(value Type*) Type:
    local Type
    unsafe:
        local = *value
    ..
    ret local
..

pub loadStatementNode(value Stmt*) Stmt:
    local Stmt
    unsafe:
        local = *value
    ..
    ret local
..

pub loadGlobalStatementNode(value GlobalStmt*) GlobalStmt:
    local GlobalStmt
    unsafe:
        local = *value
    ..
    ret local
..

pub loadExpressionNode(value Expr*) Expr:
    local Expr
    unsafe:
        local = *value
    ..
    ret local
..

pub loadLiteralNode(value Literal*) Literal:
    local Literal
    unsafe:
        local = *value
    ..
    ret local
..

pub storeTypeNode(target Type*, value Type) void:
    unsafe:
        *target = value
    ..
..

pub copyTypeNode(target Type*, source Type*) void:
    unsafe:
        *target = *source
    ..
..

pub copyExpressionNode(target Expr*, source Expr*) void:
    unsafe:
        *target = *source
    ..
..


