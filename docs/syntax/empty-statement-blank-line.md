# Empty statement / blank line

## Summary

a newline parses as an empty expression statement.

## Syntax shape

```text
\n
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A blank line can separate statements without adding an operation:

```mg
first()

second()
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use blank lines to separate nearby statements for readability; they do not perform work.

## Technical details

`src/parser.mg` (`parseStatement`): a newline becomes `Stmt.Expression(Expr.Empty)`.. A newline token is parsed as an empty expression statement. The AST stores this as `Stmt.Expression` containing `Expr.Empty` in `src/shared/node_types.mg`.
