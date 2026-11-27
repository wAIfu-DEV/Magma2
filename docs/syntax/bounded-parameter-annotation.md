# Bounded parameter annotation

## Summary

`name PointerType bounded countName` or `name PointerType bounded integer`; allowed on typed header fields/parameters.

## Syntax shape

```text
name PointerType bounded countName
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Attach a count parameter to a pointer argument when describing its extent:

```mg
data u8* bounded length
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a bounded count to document and check how many elements a pointer argument can address. The count must be another name or a numeric literal.

## Technical details

`src/parser.mg` (`parseVarDefTyped`). Its extent must be a name or numeric literal and is stored as bounded-count metadata on the argument.
