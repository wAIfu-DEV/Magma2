# Type-level generic argument lists

## Summary

can contain nested types and allow comma/newline delimiters and a trailing delimiter.

## Syntax shape

```text
[Type, ...]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Nested types can be passed as type arguments:

```mg
Map[str, Slice[u8]]
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a nonempty bracketed list of types to specialize a generic type or function. Keep each argument in the declared parameter order.

## Technical details

`src/parser.mg` (`parseType`).
