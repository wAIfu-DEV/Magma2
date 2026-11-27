# Array type/constructor expression

## Summary

`[length] ElementType`; inferred length form `[]ElementType(...)` requires an initializer list.

## Syntax shape

```text
[length] ElementType or []ElementType
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Write the requested length before the element type:

```mg
[16]u8
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use an explicit length when the array size is known at the expression site. Follow the prefix with an element type.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The array expression stores either a requested length or an inferred-length marker and its element type. The AST stores this as `Expr.Array` in `src/shared/node_types.mg`.
