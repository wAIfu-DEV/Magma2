# Union declaration

## Summary

`union Name [(impl PrototypeTypes...)] (Variant [ (fields...) ], ...)`; variants may be payload-free or carry named typed fields.

## Syntax shape

```text
union Name [(impl PrototypeTypes...)] (Variant [ (fields...) ], ...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use variants to model one of several alternatives, with payload fields where needed:

```mg
union Result (Ok(value i32), Error(code i32))
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a union when a value can be one of several named variants. Add typed fields only to variants that carry payload data.

## Technical details

`src/parser.mg` (`parseUnionDecl`). Each variant may have no fields or a parenthesized list of typed fields. Variant names must be unique. The AST stores this as `GlobalStmt.Union` in `src/shared/node_types.mg`.
