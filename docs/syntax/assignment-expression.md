# Assignment expression

## Summary

`left = right`.

## Syntax shape

```text
left = right
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Assign a new value to an existing mutable place:

```mg
count = count + 1
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `=` to update an existing mutable place. The left side must be assignable.

## Technical details

`src/parser.mg` (`parseExpression`). Assignment is right-associative and has lower precedence than the binary operators. The AST stores this as `Expr.Assign` in `src/shared/node_types.mg`.
