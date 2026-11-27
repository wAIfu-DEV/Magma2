# Unary negation

## Summary

`-expr`.

## Syntax shape

```text
-expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Negate a numeric expression with the prefix minus:

```mg
temperature := -current
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Prefix a numeric expression with `-` to negate it; use parentheses when negating a larger expression would be unclear.

## Technical details

`src/parser.mg` (`parseExprPrefix`). Prefix operators parse their operand at high precedence, so postfix operations bind inside the unary operand. The AST stores this as `Expr.Unary` in `src/shared/node_types.mg`.
