# Binary arithmetic

## Summary

`+`, `-`, `*`, `/`, `%`.

## Syntax shape

```text
left + right, left - right, left * right, left / right, left % right
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Arithmetic operators combine numeric expressions:

```mg
total := subtotal + tax
area := width * height
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use arithmetic operators on compatible numeric operands. Parenthesize mixed operations when you want to make grouping obvious.

## Technical details

`src/parser.mg` (`binaryPrecedence`). Binary operator binding powers are defined by `binaryPrecedence`: multiplication/division/remainder bind at 70, addition/subtraction at 60, shifts at 55, comparisons at 50, bitwise AND/XOR/OR at 45/40/35, logical AND/OR at 30/20, and assignment at 5. Assignment is right-associative in the Pratt parser; the other binary operators are left-associative. The AST stores this as `Expr.Binary` in `src/shared/node_types.mg`.
