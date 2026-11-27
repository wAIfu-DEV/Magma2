# Sizeof expression

## Summary

`sizeof Type`.

## Syntax shape

```text
sizeof Type
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Ask for the size of a type, not a value:

```mg
size := sizeof(Header)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `sizeof Type` when code needs the size of a type. The operand is a type name, not a runtime value.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The type is stored as the operand of `Expr.Sizeof`; size resolution is handled after parsing. The AST stores this as `Expr.Sizeof` in `src/shared/node_types.mg`.
