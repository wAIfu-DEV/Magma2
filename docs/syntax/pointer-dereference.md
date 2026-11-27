# Pointer dereference

## Summary

`*expr`.

## Syntax shape

```text
*expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Dereference a pointer when reading the pointed-to value:

```mg
value := *pointer
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `*pointer` to access the pointed-to value. Ensure the pointer is valid for the access.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The AST stores this as `Expr.Unary` in `src/shared/node_types.mg`.
