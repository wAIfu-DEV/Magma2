# Loop statement

## Summary

`loop condition: body`.

## Syntax shape

```text
loop condition: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a condition-controlled loop when the number of iterations is not fixed:

```mg
loop running:
    poll()
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `loop condition` for a condition-controlled loop. The body repeats while the condition remains true.

## Technical details

`src/parser.mg` (`parseStatement`). The AST stores this as `Stmt.Loop` in `src/shared/node_types.mg`.
