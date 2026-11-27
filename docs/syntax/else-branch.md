# Else branch

## Summary

`else: body`.

## Syntax shape

```text
else: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `else` for the remaining path after an `if` or `elif` chain:

```mg
if ready:
    start()
..
else:
    wait()
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `else` for the fallback path when no preceding condition matched.

## Technical details

`src/parser.mg` (`parseIfTail`). The AST stores this as `Stmt.Else` in `src/shared/node_types.mg`.
