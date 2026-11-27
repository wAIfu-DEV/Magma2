# `addrof` operator

## Summary

`addrof expr`.

## Syntax shape

```text
addrof expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `addrof` to take the address of a value:

```mg
pointer := addrof value
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `addrof` to explicitly request an address value in contexts that need pointer formation.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The AST stores this as `Expr.Unary` in `src/shared/node_types.mg`.
