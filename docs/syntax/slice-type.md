# Slice type

## Summary

`Type[]`.

## Syntax shape

```text
Type[]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use empty brackets after the element type for a slice:

```mg
u8[]
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a slice type for a sequence whose length travels with the view. Write the element type followed by empty brackets.

## Technical details

`src/parser.mg` (`parseType`). Empty square brackets immediately after a type create a slice type. Nonempty brackets create a templated type.
