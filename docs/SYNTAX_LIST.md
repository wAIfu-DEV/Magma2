# Magma syntax inventory

This index covers the distinct source forms recognized by the current lexer and parser. Each entry links to a user-facing sheet with its syntax, usage guidance, and implementation notes. A form being parsed does not guarantee semantic validity; name resolution, type checking, and safety checks impose further rules. The parser is hand-written, so source references point to its routines rather than to a standalone grammar file.

Notation: `...` means repetition; brackets in grammar examples denote optional/repeated metasyntax only when explicitly described. Examples in the construct paragraphs use `↵` to show a source line break. Newlines are tokens and can separate list items. A body is introduced by `:` and is parsed as a statement sequence ending at `..` (see Body and block forms); indentation itself is not parsed as a delimiter.

## Lexical forms

**Names / identifiers.** Syntax: ASCII letters and digits plus `_` after an initial letter or `_`; keyword spellings are tokenized separately. Some name positions accept the keyword `to` as a name (`parseName`, `isNameToken`). See the [detailed guide](syntax/names-identifiers.md) for usage examples and technical notes. Example: `answer i32 = 42`.

**Decimal numeric literals.** Syntax: digit-started numeric text, optional leading `-`, decimal point; lexer accepts digits, `.` and `-` in a number token. Exponent notation is not a distinct lexer form (`lexer.mg:toggleNumberMode`, `lexer.mg:run`). See the [detailed guide](syntax/decimal-numeric-literals.md) for usage examples and technical notes. Example: `count i32 = 42 ↵ ratio f64 = -3.5`.

**Hexadecimal numeric literals.** Syntax: `0x...` / `0X...` with hex digits; token representation includes the language's synthetic `u` prefix (`lexer.mg:toggleNumberMode`, `lexer.mg:lexHexNum`). See the [detailed guide](syntax/hexadecimal-numeric-literals.md) for usage examples and technical notes. Example: `mask u32 = 0x00ff`.

**String literals.** Syntax: double-quoted, may span source newlines; backslash escapes include `\a`, `\b`, `\f`, `\n`, `\r`, `\t`, `\v`, `\\`, `\'`, `\"` (and escaped backtick handling in character literals) (`lexer.mg:toggleStringMode`, `escapeChar`). See the [detailed guide](syntax/string-literals.md) for usage examples and technical notes. Example: `print("hello\n")`.

**8-bit character literals.** Syntax: single-quoted, exactly one ASCII character or supported escape (`lexer.mg:lexLitChar`). See the [detailed guide](syntax/8-bit-character-literals.md) for usage examples and technical notes. Example: `letter u8 = 'A'`.

**UTF-8 character literals.** Syntax: backtick-quoted, exactly one character including non-ASCII (`lexer.mg:lexLitChar`). See the [detailed guide](syntax/utf-8-character-literals.md) for usage examples and technical notes. Example: ``symbol u32 = `λ```.

**Boolean literals.** Syntax: `true`, `false`. See the [detailed guide](syntax/boolean-literals.md) for usage examples and technical notes. Example: `enabled bool = true`.

**None literal.** Syntax: `none`. See the [detailed guide](syntax/none-literal.md) for usage examples and technical notes. Example: `value MaybeI32 = none`.

**Line comments.** Syntax: `# ...` to newline; newline remains a parser token. See the [detailed guide](syntax/line-comments.md) for usage examples and technical notes. Example: `# Number of retry attempts ↵ retries u32 = 3`.

**Multiline comments.** Syntax: `## ... ##`; newlines inside remain parser tokens (`lexer.mg:run`). See the [detailed guide](syntax/multiline-comments.md) for usage examples and technical notes. Example: `## ↵ Temporary workaround ↵ remove after backend update ↵ ##`.

**Whitespace / line endings.** Syntax: spaces, tabs, CR are skipped; LF emits a newline token; one newline before `.` continues member access outside delimited argument lists. See the [detailed guide](syntax/whitespace-line-endings.md) for usage examples and technical notes. Example: `if ready: ↵ ret 1 ↵ ..`.


## Module-level declarations and directives

**Module declaration.** Syntax: `mod name` (only one per parsed module; inspect `parseGlobalStmt`). See the [detailed guide](syntax/module-declaration.md) for usage examples and technical notes. Example: `mod example`.

**Import/use declaration.** Syntax: `use "path" [as] alias`; the alias is required and the `as` keyword is optional (`parseUseDecl`). See the [detailed guide](syntax/import-use-declaration.md) for usage examples and technical notes. Example: `use "std:strings" strings`.

**Native library link directive.** Syntax: `link "library-name"` on its own line. See the [detailed guide](syntax/native-library-link-directive.md) for usage examples and technical notes. Example: `link "raylib"`.

**Bundle directive.** Syntax: `bundle "file-path"` on its own line. See the [detailed guide](syntax/bundle-directive.md) for usage examples and technical notes. Example: `bundle "assets/icon.png"`.

**Public modifier.** Syntax: `pub` before a declaration or `use`. See the [detailed guide](syntax/public-modifier.md) for usage examples and technical notes. Example: `pub VERSION str = "1.0"`.

**Global variable modifier.** Syntax: `global name Type [= expr]`. See the [detailed guide](syntax/global-variable-modifier.md) for usage examples and technical notes. Example: `global counter u64 = 0`.

**Constant modifier.** Syntax: `const name Type = expr` or `const name := expr`. See the [detailed guide](syntax/constant-modifier.md) for usage examples and technical notes. Example: `const MAX_RETRIES u32 = 5 ↵ const GREETING := "hello"`.

**No-context function modifier.** Syntax: `noctx` before a function declaration; also a function-type modifier. See the [detailed guide](syntax/no-context-function-modifier.md) for usage examples and technical notes. Example: `noctx currentTime() u64: ↵ ret 0 ↵ ..`.

**Destructor modifier.** Syntax: `destr` before a method declaration. See the [detailed guide](syntax/destructor-modifier.md) for usage examples and technical notes. Example: `destr Buffer.free() void: ↵ ret ↵ ..`.

**Combined declaration modifiers.** Syntax: supported modifier prefixes can be stacked where the target declaration permits them (`pub`, `global`, `const`, `noctx`, `destr`; parser validates combinations). See the [detailed guide](syntax/combined-declaration-modifiers.md) for usage examples and technical notes. Example: `pub const VERSION str = "1.0"`.

**Variable declaration with explicit type.** Syntax: `name Type [= expr]`. See the [detailed guide](syntax/variable-declaration-with-explicit-type.md) for usage examples and technical notes. Example: `count u32 = 0 ↵ nextCount u32`.

**Inferred variable declaration.** Syntax: `name := expr`. See the [detailed guide](syntax/inferred-variable-declaration.md) for usage examples and technical notes. Example: `message := "ready"`.

**Function declaration.** Syntax: `name(args...) ReturnType: body`; the absence of a newline between its header and return type distinguishes this from a struct declaration. See the [detailed guide](syntax/function-declaration.md) for usage examples and technical notes. Example: `add(left i32, right i32) i32: ↵ ret left + right ↵ ..`.

**Generic function declaration.** Syntax: `name[TypeParams...](args...) ReturnType: body`. See the [detailed guide](syntax/generic-function-declaration.md) for usage examples and technical notes. Example: `identity[T](value T) T: ↵ ret value ↵ ..`.

**Struct declaration.** Syntax: `name(fields...)`; generic parameters may be supplied as `name[TypeParams...](fields...)`. See the [detailed guide](syntax/struct-declaration.md) for usage examples and technical notes. Example: `Point(x f64, y f64)`.

**Inferred struct constructor.** Syntax: `.(field = expr, ...)`; the struct type comes from an expected type, and all fields must be named. See the [detailed guide](syntax/inferred-struct-constructor.md) for usage examples and technical notes. Example: `value Point = .(x = 0.0, y = 0.0)`.

**Implementation struct declaration.** Syntax: `Name impl PrototypeTypes... (fields...)`. See the [detailed guide](syntax/implementation-struct-declaration.md) for usage examples and technical notes. Example: `DrawablePoint impl Drawable (x f64, y f64)`.

**Method declaration.** Syntax: `Owner.method(args...) ReturnType: body`. See the [detailed guide](syntax/method-declaration.md) for usage examples and technical notes. Example: `Point.length() f64: ↵ ret this.x ↵ ..`.

**Generic-owner method declaration.** Syntax: `Owner[TypeArgs...].method(args...) ReturnType: body`. See the [detailed guide](syntax/generic-owner-method-declaration.md) for usage examples and technical notes. Example: `Vector[T].first() T: ↵ ret this.data[0] ↵ ..`.

**External function declaration.** Syntax: `ext languageName externalSymbol(args...) ReturnType`; optionally prefixed `pub` or `noctx`. See the [detailed guide](syntax/external-function-declaration.md) for usage examples and technical notes. Example: `ext puts puts(text str) i32`.

**Alias declaration.** Syntax: `alias Name = Type`. See the [detailed guide](syntax/alias-declaration.md) for usage examples and technical notes. Example: `alias UserId = u64`.

**Union declaration.** Syntax: `union Name [(impl PrototypeTypes...)] (Variant [ (fields...) ], ...)`; variants may be payload-free or carry named typed fields. See the [detailed guide](syntax/union-declaration.md) for usage examples and technical notes. Example: `union Result (Ok(value i32), Error(code i32))`.

**Enum declaration and contextual variant access.** Syntax: `enum Name BackingType (Variant [= expr], ...)`; `.Variant` access is resolved from an expected enum type. See the [detailed guide](syntax/enum-declaration.md) for usage examples and technical notes. Example: `enum Color u8 (Red, Green, Blue = 4)`.

**Prototype declaration.** Syntax: `proto Name [(impl PrototypeTypes...)] (method(args...) ReturnType, ...)`; individual requirements may be prefixed `noctx`. See the [detailed guide](syntax/prototype-declaration.md) for usage examples and technical notes. Example: `proto Drawable (draw(canvas Canvas*) void)`.

**Module platform-pruning directive.** Syntax: `@platform("platform", ...)`; controls whether the following declaration is parsed (`parseGlobalStmt`). See the [detailed guide](syntax/module-platform-pruning-directive.md) for usage examples and technical notes. Example: `@platform("linux") ↵ linuxSleep(ms u32) void: ↵ ret ↵ ..`.

**Module-level inline LLVM.** Syntax: `llvm "LLVM text"` on its own line. See the [detailed guide](syntax/module-level-inline-llvm.md) for usage examples and technical notes. Example: `llvm "declare void @abort()"`.


## Names, headers, and lists

**Simple name.** Syntax: `name`. See the [detailed guide](syntax/simple-name.md) for usage examples and technical notes. Example: `counter`.

**Composite declaration name.** Syntax: `Owner.member`; used for method declarations and selected type/name contexts. See the [detailed guide](syntax/composite-declaration-name.md) for usage examples and technical notes. Example: `Point.length`.

**Typed field / parameter.** Syntax: `name Type`. See the [detailed guide](syntax/typed-field-parameter.md) for usage examples and technical notes. Example: `width u32`.

**Bounded parameter annotation.** Syntax: `name PointerType bounded countName` or `name PointerType bounded integer`; allowed on typed header fields/parameters. See the [detailed guide](syntax/bounded-parameter-annotation.md) for usage examples and technical notes. Example: `data u8* bounded length`.

**Header argument list.** Syntax: `(name Type, ...)`; comma or newline separators and trailing separator accepted. See the [detailed guide](syntax/header-argument-list.md) for usage examples and technical notes. Example: `(x f64, y f64)`.

**Generic parameter list.** Syntax: `[TypeName, ...]` (same type parser is used for arguments, with declaration registration imposing parameter rules). See the [detailed guide](syntax/generic-parameter-list.md) for usage examples and technical notes. Example: `[T, U]`.

**Template type-argument list.** Syntax: `[Type, ...]`. See the [detailed guide](syntax/template-type-argument-list.md) for usage examples and technical notes. Example: `[u8, u64]`.

**Call argument list.** Syntax: `(expr, ...)`; newline separators and trailing separator accepted; newlines separate arguments rather than continuing member access. See the [detailed guide](syntax/call-argument-list.md) for usage examples and technical notes. Example: `(left, right)`.

**Parenthesized grouping.** Syntax: `(expr)`. See the [detailed guide](syntax/parenthesized-grouping.md) for usage examples and technical notes. Example: `(a + b) * c`.

**Comma-separated lists.** Syntax: the parser uses commas and, in several lists, newlines as separators; the accepted list contexts are call args, type args, headers, prototypes, unions, enums, and bounded clauses. See the [detailed guide](syntax/comma-separated-lists.md) for usage examples and technical notes. Example: `first, ↵ second,`.


## Types

**Named type.** Syntax: `Name` (including composite names where permitted). See the [detailed guide](syntax/named-type.md) for usage examples and technical notes. Example: `Point`.

**Pointer type.** Syntax: `Type*` (postfix; may repeat). See the [detailed guide](syntax/pointer-type.md) for usage examples and technical notes. Example: `Point* ↵ Point**`.

**Slice type.** Syntax: `Type[]`. See the [detailed guide](syntax/slice-type.md) for usage examples and technical notes. Example: `u8[]`.

**Templated type.** Syntax: `Type[TypeArgs...]`. See the [detailed guide](syntax/templated-type.md) for usage examples and technical notes. Example: `HashMap[str, u64]`.

**Owned type.** Syntax: `$Type` (prefix). See the [detailed guide](syntax/owned-type.md) for usage examples and technical notes. Example: `buffer $Buffer`.

**Throwing type.** Syntax: `!Type` (prefix). See the [detailed guide](syntax/throwing-type.md) for usage examples and technical notes. Example: `read(path str) !File`.

**Combined type qualifiers.** Syntax: `$`, `!`, and `noctx` prefixes can be consumed in sequence; ownership and throwing wrappers are applied around the parsed type. See the [detailed guide](syntax/combined-type-qualifiers.md) for usage examples and technical notes. Example: `!$File ↵ noctx fn(u32) void`.

**Function type.** Syntax: `fn(ArgTypes...) ReturnType`. See the [detailed guide](syntax/function-type.md) for usage examples and technical notes. Example: `callback fn(u32) bool`.

**Function type without `fn` keyword.** Syntax: `(ArgTypes...) ReturnType`. See the [detailed guide](syntax/function-type-without-fn-keyword.md) for usage examples and technical notes. Example: `callback (u32) bool`.

**No-context function type.** Syntax: `noctx fn(ArgTypes...) ReturnType` (the parser also accepts `noctx` before the parenthesized form). See the [detailed guide](syntax/no-context-function-type.md) for usage examples and technical notes. Example: `clock noctx fn() u64`.

**Compiler-known type directive.** Syntax: `@compiler_known_type("name")`. See the [detailed guide](syntax/compiler-known-type-directive.md) for usage examples and technical notes. Example: `PlatformWord @compiler_known_type("platform_word")`.

**Type-level generic argument lists.** Syntax: can contain nested types and allow comma/newline delimiters and a trailing delimiter. See the [detailed guide](syntax/type-level-generic-argument-lists.md) for usage examples and technical notes. Example: `Map[str, Slice[u8]]`.


## Statements and bodies

**Expression statement.** Syntax: `expr`. See the [detailed guide](syntax/expression-statement.md) for usage examples and technical notes. Example: `logMessage("started")`.

**Local typed variable declaration.** Syntax: `name Type [= expr]`. See the [detailed guide](syntax/local-typed-variable-declaration.md) for usage examples and technical notes. Example: `result i32 = 42`.

**Local inferred variable declaration.** Syntax: `name := expr`. See the [detailed guide](syntax/local-inferred-variable-declaration.md) for usage examples and technical notes. Example: `result := calculate()`.

**Two-name destructure declaration.** Syntax: `valueName, errorName := expression` (`parseDestructureStatement`). See the [detailed guide](syntax/two-name-destructure-declaration.md) for usage examples and technical notes. Example: `value, err := readFile(path)`.

**Typed two-name destructure declaration.** Syntax: `valueName ValueType, errorName ErrorType = expression` (`parseVariableStatement`). See the [detailed guide](syntax/typed-two-name-destructure-declaration.md) for usage examples and technical notes. Example: `value File, err Error = openFile(path)`.

**Return without a value.** Syntax: `ret`. See the [detailed guide](syntax/return-without-a-value.md) for usage examples and technical notes. Example: `ret`.

**Return with a value.** Syntax: `ret expr`. See the [detailed guide](syntax/return-with-a-value.md) for usage examples and technical notes. Example: `ret total`.

**Throw statement.** Syntax: `throw expr`. See the [detailed guide](syntax/throw-statement.md) for usage examples and technical notes. Example: `throw err`.

**Break statement.** Syntax: `break`. See the [detailed guide](syntax/break-statement.md) for usage examples and technical notes. Example: `break`.

**Continue statement.** Syntax: `continue`. See the [detailed guide](syntax/continue-statement.md) for usage examples and technical notes. Example: `continue`.

**If statement.** Syntax: `if condition: body`. See the [detailed guide](syntax/if-statement.md) for usage examples and technical notes. Example: `if count > 0: ↵ ret count ↵ ..`.

**Elif branch.** Syntax: `elif condition: body`. See the [detailed guide](syntax/elif-branch.md) for usage examples and technical notes. Example: `if code == 200: ↵ ret true ↵ .. ↵ elif code == 404: ↵ ret false ↵ ..`.

**Else branch.** Syntax: `else: body`. See the [detailed guide](syntax/else-branch.md) for usage examples and technical notes. Example: `if ready: ↵ start() ↵ .. ↵ else: ↵ wait() ↵ ..`.

**Loop statement.** Syntax: `loop condition: body`. See the [detailed guide](syntax/loop-statement.md) for usage examples and technical notes. Example: `loop running: ↵ poll() ↵ ..`.

**For-range statement.** Syntax: `for index := initial to bound: body`. See the [detailed guide](syntax/for-range-statement.md) for usage examples and technical notes. Example: `for i := 0 to limit: ↵ visit(i) ↵ ..`.

**Typed for-range statement.** Syntax: `for index Type = initial to bound: body`. See the [detailed guide](syntax/typed-for-range-statement.md) for usage examples and technical notes. Example: `for i u32 = 0 to limit: ↵ visit(i) ↵ ..`.

**Match statement.** Syntax: `match expression as binding: arms`; `as binding` is required. Arms are `case Union.Variant: body` and optional `else: body`; close the match with `..` (`parseMatchStmt`). See the [detailed guide](syntax/match-statement.md) for usage examples and technical notes. Example: `match result as value: ↵ case Result.Ok: ↵ consume(value) ↵ case Result.Error: ↵ report(value) ↵ ..`.

**Deferred expression.** Syntax: `defer expr`. See the [detailed guide](syntax/deferred-expression.md) for usage examples and technical notes. Example: `defer file.close()`.

**Deferred block.** Syntax: `defer: body`. See the [detailed guide](syntax/deferred-block.md) for usage examples and technical notes. Example: `defer: ↵ flush() ↵ close() ↵ ..`.

**On-error expression handler.** Syntax: `onerror expr`. See the [detailed guide](syntax/on-error-expression-handler.md) for usage examples and technical notes. Example: `onerror release(resource)`.

**On-error block handler.** Syntax: `onerror: body`. See the [detailed guide](syntax/on-error-block-handler.md) for usage examples and technical notes. Example: `onerror: ↵ rollback() ↵ logFailure() ↵ ..`.

**Unsafe expression form.** Syntax: `unsafe expr`. See the [detailed guide](syntax/unsafe-expression-form.md) for usage examples and technical notes. Example: `unsafe pointer[0]`.

**Unsafe block form.** Syntax: `unsafe: body`. See the [detailed guide](syntax/unsafe-block-form.md) for usage examples and technical notes. Example: `unsafe: ↵ pointer[0] = value ↵ ..`.

**Bounded predicates block.** Syntax: `bounded predicate, ...: body`. See the [detailed guide](syntax/bounded-predicates-block.md) for usage examples and technical notes. Example: `bounded index < length: ↵ use(data[index]) ↵ ..`.

**Bounded pointer/extent clause.** Syntax: `bounded pointer by extent, ...: body`; may be combined with predicates. See the [detailed guide](syntax/bounded-pointer-extent-clause.md) for usage examples and technical notes. Example: `bounded data by length: ↵ consume(data, length) ↵ ..`.

**Statement-level inline LLVM.** Syntax: `llvm "LLVM text"` on its own line. See the [detailed guide](syntax/statement-level-inline-llvm.md) for usage examples and technical notes. Example: `llvm "call void @abort()"`.

**With statement / scoped cleanup form.** Syntax: `with local-statement then deferred-expression: body`; the parser lowers this to a scope containing the local, a deferred expression, and the body (`parseWithStmt`). See the [detailed guide](syntax/with-statement-scoped-cleanup-form.md) for usage examples and technical notes. Example: `with file File = open(path) then file.close(): ↵ process(file) ↵ ..`.

**Body / block.** Syntax: `: statement... ..`; nested bodies are parsed recursively. The closing `..` token also terminates a return/break/continue line without consuming the next statement. See the [detailed guide](syntax/body-block.md) for usage examples and technical notes. Example: `run() void: ↵ prepare() ↵ execute() ↵ ..`.

**Empty statement / blank line.** Syntax: a newline parses as an empty expression statement. See the [detailed guide](syntax/empty-statement-blank-line.md) for usage examples and technical notes. Example: `first() ↵ second()`.


## Expressions

**Name expression.** Syntax: `name`. See the [detailed guide](syntax/name-expression.md) for usage examples and technical notes. Example: `ret count`.

**Zero expression.** Syntax: `zero`; its type comes from the surrounding expected type, and it lowers to an LLVM zero initializer. See the [detailed guide](syntax/zero-expression.md) for usage examples and technical notes. Example: `f(.(x = value, y = zero))`.

**Literal expression.** Syntax: any literal form listed above. See the [detailed guide](syntax/literal-expression.md) for usage examples and technical notes. Example: ``42 ↵ "hello" ↵ true ↵ none ↵ 'x' ↵ `λ```.

**Array type/constructor expression.** Syntax: `[length] ElementType`; inferred length form `[]ElementType(...)` requires an initializer list. See the [detailed guide](syntax/array-type-constructor-expression.md) for usage examples and technical notes. Example: `[16]u8`.

**Array initializer / constructor call.** Syntax: `[]ElementType(expr, ...)` (also explicit-length array expressions are represented by `[length]Type`; check semantics for initializer rules). See the [detailed guide](syntax/array-initializer-constructor-call.md) for usage examples and technical notes. Example: `[]u8(1, 2, 3)`.

**Function call.** Syntax: `callee(args...)`. See the [detailed guide](syntax/function-call.md) for usage examples and technical notes. Example: `add(2, 3)`.

**Templated call.** Syntax: `callee[TypeArgs...](args...)`. See the [detailed guide](syntax/templated-call.md) for usage examples and technical notes. Example: `makePair[i32, str](1, "one")`.

**Generic application/reference.** Syntax: `callee[TypeArgs...]` in the parser's generic-reference context. See the [detailed guide](syntax/generic-application-reference.md) for usage examples and technical notes. Example: `callbacks.pushRight[Item, Allocator](item, allocator)`.

**Subscript expression.** Syntax: `owner[index]`. See the [detailed guide](syntax/subscript-expression.md) for usage examples and technical notes. Example: `bytes[index]`.

**Member access.** Syntax: `owner.member`; a chain may continue after one newline outside delimited argument lists. See the [detailed guide](syntax/member-access.md) for usage examples and technical notes. Example: `point.x`.

**Move expression.** Syntax: `move expr`. See the [detailed guide](syntax/move-expression.md) for usage examples and technical notes. Example: `destination := move source`.

**Try expression.** Syntax: `try expr` (intended for call expressions). See the [detailed guide](syntax/try-expression.md) for usage examples and technical notes. Example: `contents := try read(path)`.

**Sizeof expression.** Syntax: `sizeof Type`. See the [detailed guide](syntax/sizeof-expression.md) for usage examples and technical notes. Example: `size := sizeof(Header)`.

**Unary negation.** Syntax: `-expr`. See the [detailed guide](syntax/unary-negation.md) for usage examples and technical notes. Example: `temperature := -current`.

**Logical not.** Syntax: `not expr`. See the [detailed guide](syntax/logical-not.md) for usage examples and technical notes. Example: `if not ready: ↵ wait() ↵ ..`.

**Bitwise complement.** Syntax: `~expr`. See the [detailed guide](syntax/bitwise-complement.md) for usage examples and technical notes. Example: `inverted := ~mask`.

**Pointer dereference.** Syntax: `*expr`. See the [detailed guide](syntax/pointer-dereference.md) for usage examples and technical notes. Example: `value := *pointer`.

**Reference/address operator.** Syntax: `&expr`. See the [detailed guide](syntax/reference-address-operator.md) for usage examples and technical notes. Example: `pointer := &value`.

**`addrof` operator.** Syntax: `addrof expr`. See the [detailed guide](syntax/addrof-operator.md) for usage examples and technical notes. Example: `pointer := addrof value`.

**Assignment expression.** Syntax: `left = right`. See the [detailed guide](syntax/assignment-expression.md) for usage examples and technical notes. Example: `count = count + 1`.

**Inferred assignment expression.** Syntax: `left := right` (also used for declarations in declaration contexts). See the [detailed guide](syntax/inferred-assignment-expression.md) for usage examples and technical notes. Example: `message := "ready"`.

**Binary arithmetic.** Syntax: `+`, `-`, `*`, `/`, `%`. See the [detailed guide](syntax/binary-arithmetic.md) for usage examples and technical notes. Example: `total := subtotal + tax ↵ area := width * height`.

**Comparison.** Syntax: `==`, `!=`, `<`, `>`, `<=`, `>=`. See the [detailed guide](syntax/comparison.md) for usage examples and technical notes. Example: `if count >= limit: ↵ stop() ↵ ..`.

**Logical conjunction / disjunction.** Syntax: `&&`, `||`. See the [detailed guide](syntax/logical-conjunction-disjunction.md) for usage examples and technical notes. Example: `if connected && ready: ↵ send() ↵ ..`.

**Bitwise operators.** Syntax: binary `&`, `|`, `^`, `<<`, `>>`; `~` is prefix bitwise complement. See the [detailed guide](syntax/bitwise-operators.md) for usage examples and technical notes. Example: `flags := readFlags() & mask ↵ shifted := flags << 2`.

**Inline LLVM expression.** Syntax: `@llvm("operation", operand..., ResultType)`; the final argument is a type. See the [detailed guide](syntax/inline-llvm-expression.md) for usage examples and technical notes. Example: `value := @llvm("add", left, right, i32)`.

**Embed expression.** Syntax: `@embed("path")`. See the [detailed guide](syntax/embed-expression.md) for usage examples and technical notes. Example: `icon := @embed("assets/icon.png")`.

**Compiler-known expression.** Syntax: `@compiler_known("name")`. See the [detailed guide](syntax/compiler-known-expression.md) for usage examples and technical notes. Example: `version := @compiler_known("version")`.


## Punctuation and reserved words checklist

Lexer punctuation tokens: `=`, `:=`, `(`, `)`, `[`, `]`, `{`, `}`, `:`, `.`, `..`, `!`, `,`, `-`, `+`, `$`, `*`, `&`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `|`, `^`, `~`, `<<`, `>>`, `&&`, `||`, `@`, `%`, `/`. Braces are tokenized but are not consumed by a source grammar production in the current parser. See [punctuation and reserved words](syntax/punctuation-and-reserved-words.md) for the full token reference. Example: `a + b` uses an operator token, and `call(value)` uses delimiter tokens.

Reserved keyword spellings: `mod`, `use`, `link`, `bundle`, `pub`, `ret`, `throw`, `llvm`, `if`, `elif`, `else`, `true`, `false`, `none`, `loop`, `try`, `defer`, `onerror`, `sizeof`, `continue`, `break`, `ext`, `addrof`, `destr`, `const`, `alias`, `for`, `to`, `bounded`, `unsafe`, `noctx`, `not`, `fn`, `as`, `union`, `match`, `case`, `global`, `enum`, `with`, `then`, `zero`.

`to` is also accepted as a name in designated name positions. `then` is used by `with`; all other keyword spellings above have a corresponding construct or token use in the parser.

## Implementation source map

- `src/lexer.mg` — comments, literals, escapes, tokenization, punctuation.
- `src/shared/token_types.mg` — complete token and keyword spelling tables.
- `src/parser.mg` — `parseType`, `parseExpression`, `parseExprPrefix`, `parseStatement`, `parseBody`, `parseGlobalStmt`, `parseProtoDecl`, `parseUnionDecl`, `parseEnumDecl`, and `parseUseDecl`.
- `src/shared/node_types.mg` — AST node variants used as a cross-check for parsed construct categories.
