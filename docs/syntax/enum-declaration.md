# Enum declaration

## Summary

`enum Name BackingType (Variant [= expr], ...)`.

## Syntax shape

```text
enum Name BackingType (Variant [= expr], ...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use an enum for a fixed set of named values:

```mg
enum Color u8 (Red, Green, Blue = 4)
color Color = .Red
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use an enum for a closed set of named values with one explicit backing type. Omit variant values for implicit numbering or assign selected values with `=`.

An enum variant can also be written as `.Variant` when an expected enum type is available, for example `color Color = .Red` or as an argument to a function whose parameter type is `Color`. The checker resolves the variant against that expected enum. If the type is not known from context, use qualified access such as `Color.Red`.

## Technical details

`src/parser.mg` (`parseEnumDecl`, `parseExprPrefix`). The backing type is explicit. Variant values may be implicit or assigned an expression after `=`. Contextual `.Variant` access is checked against an expected enum type by `src/link_checker.mg`. The AST stores declarations as `GlobalStmt.Enum` and shorthand access as `Expr.EnumVariant` in `src/shared/node_types.mg`.
