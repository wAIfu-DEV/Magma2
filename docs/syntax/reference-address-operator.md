# Reference/address operator

## Summary

`&expr`.

## Syntax shape

```text
&expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `&` where the expression needs an address or pointer:

```mg
pointer := &value
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `&value` when an expression needs a pointer to an addressable value.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The AST stores this as `Expr.Unary` in `src/shared/node_types.mg`.
