# On-error block handler

## Summary

`onerror: body`.

## Syntax shape

```text
onerror: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a block handler when the error path needs several actions:

```mg
onerror:
    rollback()
    logFailure()
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a block error handler when recovery requires multiple statements.

## Technical details

`src/parser.mg` (`parseStatement`). The block form parses a body to run for the current scope’s error path. The AST stores this as `Stmt.OnError` with a body in `src/shared/node_types.mg`.
