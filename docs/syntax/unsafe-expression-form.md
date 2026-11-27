# Unsafe expression form

## Summary

`unsafe expr`.

## Syntax shape

```text
unsafe expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Wrap the operation that requires unsafe access:

```mg
unsafe pointer[0]
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Keep an unsafe expression scope as small as practical and use it only for operations that require unsafe access.

## Technical details

`src/parser.mg` (`parseStatement`). This marks the following expression as unsafe; semantic safety checks interpret the scope. The AST stores this as `Stmt.Unsafe` with an expression in `src/shared/node_types.mg`.
