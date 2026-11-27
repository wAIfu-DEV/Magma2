# Bitwise operators

## Summary

`&`, `|`, `^`, `~`, `<<`, `>>` (where prefix/postfix parsing permits).

## Syntax shape

```text
&, |, ^, ~, <<, >>
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use bitwise operators for integer masks and shifts:

```mg
flags := readFlags() & mask
shifted := flags << 2
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use bitwise operators on integer values for masks and shifts. `~` is prefix; `&`, `|`, `^`, `<<`, and `>>` are infix.

## Technical details

`src/parser.mg` (`binaryPrecedence, parseExprPrefix`). Binary operator binding powers are defined by `binaryPrecedence`: multiplication/division/remainder bind at 70, addition/subtraction at 60, shifts at 55, comparisons at 50, bitwise AND/XOR/OR at 45/40/35, logical AND/OR at 30/20, and assignment at 5. Assignment is right-associative in the Pratt parser; the other binary operators are left-associative. The AST stores this as `Expr.Binary` for infix forms and `Expr.Unary` for prefix `~` in `src/shared/node_types.mg`.
