# Struct declaration

## Summary

`name(fields...)`; generic parameters may be supplied as `name[TypeParams...](fields...)`.

## Syntax shape

```text
name(fields...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Declare a record by listing its named fields:

```mg
Point(x f64, y f64)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a struct to group named fields into a product type. Keep its field names unique and give each field a type.

When an initializer or call argument already determines the struct type, use the [inferred struct constructor](inferred-struct-constructor.md) form `.(field = value, ...)` to omit the repeated type name.

## Technical details

`src/parser.mg` (`parseHeader`). A struct declaration is a typed header without a function return type or body. Field names are registered in the type scope. The AST stores this as `GlobalStmt.Struct` in `src/shared/node_types.mg`.
