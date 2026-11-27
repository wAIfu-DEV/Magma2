# Typed for-range statement

## Summary

`for index Type = initial to bound: body`.

## Syntax shape

```text
for index Type = initial to bound: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Choose an explicit type for the range index when needed:

```mg
for i u32 = 0 to limit:
    visit(i)
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Choose the explicit index type when inference would be unclear or when the loop needs a specific integer type.

## Technical details

`src/parser.mg` (`parseForStmt`). The AST stores this as `Stmt.ForLoop` in `src/shared/node_types.mg`.
