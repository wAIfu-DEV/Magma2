# Elif branch

## Summary

`elif condition: body`.

## Syntax shape

```text
elif condition: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Add `elif` after an `if` body to test another condition:

```mg
if code == 200:
    ret true
..
elif code == 404:
    ret false
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `elif` after an `if` or another `elif` when conditions should be checked in sequence.

## Technical details

`src/parser.mg` (`parseIfTail`). The AST stores this as `Stmt.Elif` in `src/shared/node_types.mg`.
