# Array initializer / constructor call

## Summary

`[]ElementType(expr, ...)` (also explicit-length array expressions are represented by `[length]Type`; check semantics for initializer rules).

## Syntax shape

```text
[]ElementType(value, ...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use inferred length with an initializer list:

```mg
[]u8(1, 2, 3)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use inferred length when the initializer elements should determine the array size. The initializer list is required.

## Technical details

`src/parser.mg` (`parseExprPrefix, parseCallArgs`). The `[]ElementType` prefix must be followed by parenthesized initializer arguments; these are parsed as ordinary postfix call arguments. Newlines separate initializer expressions, so member access cannot continue across a newline inside the list. The AST stores this as `Expr.Array` followed by ordinary call syntax in `src/shared/node_types.mg`.
