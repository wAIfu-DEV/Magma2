# Local inferred variable declaration

## Summary

`name := expr`.

## Syntax shape

```text
name := expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use inference when the initializer already makes the intended type clear:

```mg
result := calculate()
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use an inferred local when its initializer makes the intended type clear. The value is evaluated as part of the declaration.

## Technical details

`src/parser.mg` (`parseVariableStatement`). The AST stores this as `Expr.VarDefAssign` in `src/shared/node_types.mg`.
