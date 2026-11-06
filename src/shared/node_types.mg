mod node_types

use "std:array" arr

# Array is used here as it allows growable list behavior with the same memory footprint as a slice (128b)

pub proto Node()

pub Root impl Node(
    statements arr.Array[GlobalStmt*]
)

pub Header impl Node(
    id u64
    name str
    fields arr.Array[Expr*]
    typeArgs arr.Array[Type*]
)

pub union Name impl Node(
    Simple(name str)
    Composite(names arr.Array[str])
)

pub union Type impl Node(
    Named(id u64)
    Pointer(toType Type*)
    Templated(owner Type*, args arr.Array[Type*])
    Slice(ofType Type*)
)

pub union Stmt impl Node(
    Body(statements arr.Array[Stmt*])
    If(condition Expr*, body Stmt*)
    Elif(condition Expr*, body Stmt*)
    Else(body Stmt*)
    Loop(condition Expr*, body Stmt*)
    ForLoop(index Expr*, bound Expr*, body Stmt*)
)

pub union GlobalStmt impl Node(
    Struct(header Header*)
    Function(header Header*, body Stmt*)
    Method(ownerType Type*, name Name*, func GlobalStmt*)
    Union(id u64, variants arr.Array[Header*])
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
    VarDef(type Type*, name str)
    VarDefAssign(type Type*, name str, assignment Expr*)
    VarDefAssignDestructure(type Type*, nameValue str, nameError str, call Expr*)
    Unary(type Type*, op u8, operand Expr*)
    Binary(type Type*, op u8, left Expr*, right Expr*)
    DirectCall(type Type*, declId u64, args arr.Array[Expr*], typeArgs arr.Array[Type*])
    IndirectCall(type Type*, owner Expr*, args arr.Array[Expr*], typeArgs arr.Array[Type*])
    Try(type Type*, call Expr*)
    Assign(type Type*, assignee Expr*, expr Expr*)
    Return(expr Expr*)
    Throw(expr Expr*)
)


