# Bitwise complement

## Summary

`~expr`.

## Syntax shape

```text
~expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Invert the bits of an integer value:

```mg
inverted := ~mask
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `~` to invert the bits of an integer mask; it is a prefix operator.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The AST stores this as `Expr.Unary` in `src/shared/node_types.mg`.
