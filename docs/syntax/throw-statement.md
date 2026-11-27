# Throw statement

## Summary

`throw expr`.

## Syntax shape

```text
throw expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Throw an error value from a throwing function:

```mg
throw err
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `throw` to leave the current function through its error result. Throw a value compatible with the function’s throwing type.

## Technical details

`src/parser.mg` (`parseStatement`). The thrown value is stored as an expression and checked against the function’s throwing type. The AST stores this as `Expr.Throw` in `src/shared/node_types.mg`.
