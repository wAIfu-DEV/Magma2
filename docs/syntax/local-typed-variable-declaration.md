# Local typed variable declaration

## Summary

`name Type [= expr]`.

## Syntax shape

```text
name Type [= expr]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Declare a local with its type; initialization is optional:

```mg
result i32 = 42
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a typed local when you want its type explicit or when you declare it before assigning a value.

## Technical details

`src/parser.mg` (`parseVariableStatement`). The AST stores this as `Expr.VarDef` or `Expr.VarDefAssign` in `src/shared/node_types.mg`.
