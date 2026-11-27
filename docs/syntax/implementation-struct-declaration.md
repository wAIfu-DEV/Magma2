# Implementation struct declaration

## Summary

`Name impl PrototypeTypes... (fields...)`.

## Syntax shape

```text
Name impl PrototypeTypes... (fields...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

List implemented prototypes between `impl` and the field header:

```mg
DrawablePoint impl Drawable (x f64, y f64)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this form when a concrete struct declares which prototypes it implements. Place prototype types after `impl` and list fields in parentheses.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). Implemented prototype types are parsed between `impl` and the field header and stored on the declared struct. The AST stores this as `GlobalStmt.Struct` with implemented types in `src/shared/node_types.mg`.
