# Pointer type

## Summary

`Type*` (postfix; may repeat).

## Syntax shape

```text
Type*
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Add `*` after a type to form a pointer; repeated stars form nested pointers:

```mg
Point*
Point**
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a pointer when a value refers to storage rather than owning an inline value. Add one star per pointer level.

## Technical details

`src/parser.mg` (`parseType`). Postfix pointer stars are applied repeatedly, so `Type**` is parsed as a pointer to a pointer.
