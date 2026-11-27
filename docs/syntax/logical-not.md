# Logical not

## Summary

`not expr`.

## Syntax shape

```text
not expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `not` to invert a boolean condition:

```mg
if not ready:
    wait()
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `not` on a boolean expression to reverse its condition.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The AST stores this as `Expr.Unary` in `src/shared/node_types.mg`.
