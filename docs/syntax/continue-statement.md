# Continue statement

## Summary

`continue`.

## Syntax shape

```text
continue
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Skip to the next iteration of the nearest enclosing loop:

```mg
continue
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `continue` by itself to begin the next iteration of the nearest enclosing loop. It cannot take an operand.

## Technical details

`src/parser.mg` (`parseStatement`). The AST stores this as `Stmt.Continue` in `src/shared/node_types.mg`.
