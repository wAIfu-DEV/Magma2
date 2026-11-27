# For-range statement

## Summary

`for index := initial to bound: body`.

## Syntax shape

```text
for index := initial to bound: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use an inferred index for a range loop:

```mg
for i := 0 to limit:
    visit(i)
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a range loop for a sequence of index values from the initial value up to the bound. `to` separates the index initialization from that bound.

## Technical details

`src/parser.mg` (`parseForStmt`). The index is scoped to the loop. The bound is parsed once as the loop’s range bound expression. The AST stores this as `Stmt.ForLoop` in `src/shared/node_types.mg`.
