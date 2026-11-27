# Deferred block

## Summary

`defer: body`.

## Syntax shape

```text
defer: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a deferred body when cleanup needs several statements:

```mg
defer:
    flush()
    close()
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a deferred block when cleanup needs multiple ordered statements or local control flow.

## Technical details

`src/parser.mg` (`parseStatement`). A deferred body is parsed as a nested body and runs on scope exit. The AST stores this as `Stmt.Defer` with a body in `src/shared/node_types.mg`.
