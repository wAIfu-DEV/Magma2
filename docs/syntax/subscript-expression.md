# Subscript expression

## Summary

`owner[index]`.

## Syntax shape

```text
owner[index]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Index into an array or slice with a bracketed expression:

```mg
bytes[index]
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use subscripting to select an element from an indexable value. The bracket expression is the index.

## Technical details

`src/parser.mg` (`parseExpression`). A single expression is parsed between brackets and stored with the owner in `Expr.Subscript`. The AST stores this as `Expr.Subscript` in `src/shared/node_types.mg`.
