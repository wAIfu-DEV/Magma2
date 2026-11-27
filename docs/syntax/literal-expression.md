# Literal expression

## Summary

any literal form listed above.

## Syntax shape

```text
42
"text"
true
none
'x'
λ
```

These examples show the literal families accepted by the lexer; the expected type depends on the surrounding expression context.

## Example

Literal expressions include the numeric, string, boolean, none, and character forms:

```mg
42
"hello"
true
none
'x'
`λ`
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Choose the literal form matching the value you need; its concrete type is determined by the expected context and later checking.

## Technical details

`src/parser.mg` (`parseExprPrefix, parseLiteral`). The AST stores this as `Expr.Literal` in `src/shared/node_types.mg`.
