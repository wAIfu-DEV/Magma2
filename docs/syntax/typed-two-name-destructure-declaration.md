# Typed two-name destructure declaration

## Summary

`valueName ValueType, errorName ErrorType = expression` (`parseVariableStatement`).

## Syntax shape

```text
valueName ValueType, errorName ErrorType = expression
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use explicit result and error types when both bindings need declared types:

```mg
value File, err Error = openFile(path)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use explicit result and error types when inference is insufficient. The parser expects `=` after both typed bindings.

## Technical details

`src/parser.mg` (`parseVariableStatement`). The AST stores this as `Expr.VarDefAssignDestructure` with explicit types in `src/shared/node_types.mg`.
