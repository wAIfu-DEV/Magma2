# Inferred assignment expression

## Summary

`left := right` (also used for declarations in declaration contexts).

## Syntax shape

```text
left := right
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `:=` for a declaration whose type should be inferred:

```mg
message := "ready"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `:=` for declarations that infer a type; use `=` for ordinary reassignment.

## Technical details

`src/parser.mg` (`parseExpression`). In expression parsing this produces an assignment node; in declaration contexts it is also the inference marker. The AST stores this as `Expr.Assign` in `src/shared/node_types.mg`.
