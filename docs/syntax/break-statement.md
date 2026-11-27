# Break statement

## Summary

`break`.

## Syntax shape

```text
break
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Exit the nearest enclosing loop:

```mg
break
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `break` by itself to exit the nearest enclosing loop. It cannot take an operand.

## Technical details

`src/parser.mg` (`parseStatement`). The AST stores this as `Stmt.Break` in `src/shared/node_types.mg`.
