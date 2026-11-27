# Name expression

## Summary

`name`.

## Syntax shape

```text
name
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Read a named value in an expression:

```mg
ret count
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a name expression to read or refer to a value in the current scope.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The AST stores this as `Expr.Named` in `src/shared/node_types.mg`.
