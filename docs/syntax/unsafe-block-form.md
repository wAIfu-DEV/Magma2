# Unsafe block form

## Summary

`unsafe: body`.

## Syntax shape

```text
unsafe: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a block when several operations share the unsafe context:

```mg
unsafe:
    pointer[0] = value
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Group related unsafe operations in one block; the block makes the unsafe region explicit for review.

## Technical details

`src/parser.mg` (`parseStatement`). This opens an unsafe body for operations that require unsafe context. The AST stores this as `Stmt.Unsafe` with a body in `src/shared/node_types.mg`.
