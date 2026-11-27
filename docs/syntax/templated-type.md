# Templated type

## Summary

`Type[TypeArgs...]`.

## Syntax shape

```text
Type[TypeArgs...]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Apply type arguments to a generic type:

```mg
HashMap[str, u64]
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a templated type to instantiate a generic type with concrete type arguments in declaration order.

## Technical details

`src/parser.mg` (`parseType`).
