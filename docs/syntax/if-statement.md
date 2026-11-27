# If statement

## Summary

`if condition: body`.

## Syntax shape

```text
if condition: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `if` to run a body only when its condition is true:

```mg
if count > 0:
    ret count
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `if` for conditional control flow. Its condition is an expression and its body follows a colon.

## Technical details

`src/parser.mg` (`parseIfStmt`). The AST stores this as `Stmt.If` in `src/shared/node_types.mg`.
