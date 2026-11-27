# None literal

## Summary

`none`.

## Syntax shape

```text
none
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `none` for an absent optional value when the expected type permits it:

```mg
value MaybeI32 = none
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this spelling in the source position accepted by the surrounding grammar.

## Technical details

`src/shared/token_types.mg` and `src/parser.mg` (`parseExprPrefix`). `none` is represented as a literal expression and its concrete type is determined by semantic analysis.
