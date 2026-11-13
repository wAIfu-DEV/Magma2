mod tok_types

use "std:errors" errs
use "std:hash_map" hmp
use "std:cast" cast
use "std:strings" strgs

use "origin" org

pub enum TkType u8(
    NONE=0
    NAME
    LIT_STR
    LIT_NUM
    LIT_BOOL
    LIT_NONE
    LIT_CHAR8
    LIT_CHAR32
    KEYWORD
    _END
)

global TkTypeToRepr str[] = [TkType._END]str(
    TkType.NONE =     "None"
    TkType.NAME =     "Name"
    TkType.LIT_STR =  "LitStr"
    TkType.LIT_NUM =  "LitNum"
    TkType.LIT_BOOL = "LitBool"
    TkType.LIT_NONE = "LitNone"
    TkType.LIT_CHAR8 = "LitChar8"
    TkType.LIT_CHAR32 = "LitChar32"
    TkType.KEYWORD =  "Keyword"
)

pub getTkRepr(t TkType) !str:
    if t >= TkType._END:
        throw errs.wouldOverflow("t is out of bounds")
    ..
    bounded t < TkTypeToRepr.count():
        ret TkTypeToRepr[t]
    ..
..

pub enum KwType u8(
    NONE=0
    EQUAL
    PAREN_OP
    PAREN_CL
    BRACK_OP
    BRACK_CL
    BRACE_OP
    BRACE_CL
    COLON
    DOT
    DOTS
    EXCLAM
    MODULE
    USE
    LINK
    BUNDLE
    PUBLIC
    RETURN
    NEWLINE
    COMMA
    MINUS
    PLUS
    DOLLAR
    ASTERIX
    AMPERSAND
    THROW
    LLVM
    IF
    ELIF
    ELSE
    TRUE
    FALSE
    NONE_LIT
    LOOP
    CMP_EQ
    CMP_NEQ
    TRY
    DEFER
    ONERROR
    CMP_LT
    CMP_GT
    CMP_LTEQ
    CMP_GTEQ
    PIPE
    CARET
    TILDE
    SHIFT_L
    SHIFT_R
    ANDAND
    OROR
    SIZEOF
    CONTINUE
    BREAK
    AT
    EXTERN
    PERCENT
    ADDROF
    SLASH
    INFER
    DESTR
    CONST
    ALIAS
    FOR
    TO
    BOUNDED
    UNSAFE
    NOCTX
    NOT
    FN
    AS
    UNION
    MATCH
    CASE
    GLOBAL
    ENUM
    _END
)

global KwTypeToRepr str[] = [KwType._END]str(
    KwType.NONE = ""
    KwType.EQUAL = "="
    KwType.PAREN_OP = "("
    KwType.PAREN_CL = ")"
    KwType.BRACK_OP = "["
    KwType.BRACK_CL = "]"
    KwType.BRACE_OP = "{"
    KwType.BRACE_CL = "}"
    KwType.COLON = ":"
    KwType.DOT = "."
    KwType.DOTS  = ".."
    KwType.EXCLAM = "!"
    KwType.MODULE = "mod"
    KwType.USE = "use"
    KwType.LINK = "link"
    KwType.BUNDLE = "bundle"
    KwType.PUBLIC = "pub"
    KwType.RETURN = "ret"
    KwType.NEWLINE = "\n"
    KwType.COMMA = ","
    KwType.MINUS = "-"
    KwType.PLUS = "+"
    KwType.DOLLAR = "$"
    KwType.ASTERIX = "*"
    KwType.AMPERSAND = "&"
    KwType.THROW = "throw"
    KwType.LLVM = "llvm"
    KwType.IF = "if"
    KwType.ELIF = "elif"
    KwType.ELSE = "else"
    KwType.TRUE = "true"
    KwType.FALSE = "false"
    KwType.NONE_LIT = "none"
    KwType.LOOP = "loop"
    KwType.CMP_EQ = "=="
    KwType.CMP_NEQ = "!="
    KwType.TRY = "try"
    KwType.DEFER = "defer"
    KwType.ONERROR = "onerror"
    KwType.CMP_LT = "<"
    KwType.CMP_GT = ">"
    KwType.CMP_LTEQ = "<="
    KwType.CMP_GTEQ = ">="
    KwType.PIPE = "|"
    KwType.CARET = "^"
    KwType.TILDE = "~"
    KwType.SHIFT_L = "<<"
    KwType.SHIFT_R = ">>"
    KwType.ANDAND = "&&"
    KwType.OROR = "||"
    KwType.SIZEOF = "sizeof"
    KwType.CONTINUE = "continue"
    KwType.BREAK  = "break"
    KwType.AT = "@"
    KwType.EXTERN = "ext"
    KwType.PERCENT = "%"
    KwType.ADDROF = "addrof"
    KwType.SLASH = "/"
    KwType.INFER = ":="
    KwType.DESTR = "destr"
    KwType.CONST = "const"
    KwType.ALIAS = "alias"
    KwType.FOR = "for"
    KwType.TO = "to"
    KwType.BOUNDED = "bounded"
    KwType.UNSAFE = "unsafe"
    KwType.NOCTX = "noctx"
    KwType.NOT = "not"
    KwType.FN = "fn"
    KwType.AS = "as"
    KwType.UNION = "union"
    KwType.MATCH = "match"
    KwType.CASE = "case"
    KwType.GLOBAL = "global"
    KwType.ENUM = "enum"
)


global KwReprToType hmp.HashMap[KwType]
global KwFirstByteHead := [256]u8
global KwFirstByteNext := [KwType._END]u8
# The map is process-wide, so its initialized flag must be process-wide too.
global _kwMapInit bool = false

pub initKwMap() !void:
    if _kwMapInit:
        ret
    ..
    KwReprToType = try hmp.new[KwType](KwType._END, none)
    for i u64 = 0 to KwTypeToRepr.count():
        KwReprToType.setBorrowed(KwTypeToRepr[i], cast.u64to8(i))
        repr := KwTypeToRepr[i]
        if repr.countBytes() > 0:
            firstByte := strgs.byteAt(repr, 0)
            bounded i < KwFirstByteNext.count():
                bounded firstByte < KwFirstByteHead.count():
                    KwFirstByteNext[i] = KwFirstByteHead[firstByte]
                    KwFirstByteHead[firstByte] = cast.u64to8(i)
                ..
            ..
        ..
    ..
    _kwMapInit = true
..

pub getKwFirstByteHead(byte u8) u8:
    bounded byte < KwFirstByteHead.count():
        ret KwFirstByteHead[byte]
    ..
    ret 0
..

pub getKwFirstByteNext(k KwType) KwType:
    bounded k < KwFirstByteNext.count():
        ret cast.u64to8(KwFirstByteNext[k])
    ..
    ret KwType.NONE
..

pub getKwReprSize() u64:
    ret KwTypeToRepr.count()
..

pub getKwRepr(k KwType) !str:
    if k >= KwType._END:
        throw errs.outOfBounds("k is out of bounds")
    ..
    bounded k < KwTypeToRepr.count():
        ret KwTypeToRepr[k]
    ..
..

pub getKwFromRepr(repr str) !KwType:
    if not _kwMapInit:
        throw errs.failure("KwReprToType not initialized")
    ..
    ret try KwReprToType.get(repr)
..

pub Token(
    repr str
    pos org.FilePos
    type TkType
    kwType KwType
)
