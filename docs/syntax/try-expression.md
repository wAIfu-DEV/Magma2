# Try expression

## Summary

`try expr` (intended for call expressions).

## Syntax shape

```text
try expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Propagate an error from a throwing call in a throwing function:

```mg
contents := try read(path)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `try` to propagate an error from a throwing call in a function that can itself return that error.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The parser wraps the following high-precedence expression. Later semantic checks determine whether its operand is a valid throwing call. The AST stores this as `Expr.Try` in `src/shared/node_types.mg`.
