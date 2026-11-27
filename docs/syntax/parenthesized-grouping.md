# Parenthesized grouping

## Summary

`(expr)`.

## Syntax shape

```text
(expression)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use parentheses to make the intended grouping explicit:

```mg
(a + b) * c
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Add parentheses when you want an expression grouped before surrounding operators are applied. The parentheses do not change its value or type.

## Technical details

`src/parser.mg` (`parseExprPrefix`): the parser returns the inner expression node, so grouping does not add an AST wrapper.. Parentheses return the enclosed expression node directly; they do not create a separate grouping AST node.
