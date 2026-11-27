# Logical conjunction / disjunction

## Summary

`&&`, `||`.

## Syntax shape

```text
left && right and left || right
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Combine boolean conditions with `&&` and `||`:

```mg
if connected && ready:
    send()
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `&&` and `||` to combine boolean expressions; `&&` binds more tightly than `||`.

## Technical details

`src/parser.mg` (`binaryPrecedence`). Binary operator binding powers are defined by `binaryPrecedence`: multiplication/division/remainder bind at 70, addition/subtraction at 60, shifts at 55, comparisons at 50, bitwise AND/XOR/OR at 45/40/35, logical AND/OR at 30/20, and assignment at 5. Assignment is right-associative in the Pratt parser; the other binary operators are left-associative. The AST stores this as `Expr.Binary` in `src/shared/node_types.mg`.
