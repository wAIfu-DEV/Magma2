# Owned type

## Summary

`$Type` (prefix).

## Syntax shape

```text
$Type
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Prefix an owned value type with `$` where ownership is part of the declaration:

```mg
buffer $Buffer
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `$T` for a type with ownership semantics when the value is responsible for the resource. Follow the type’s ownership contract when moving or releasing it.

## Technical details

`src/parser.mg` (`parseType`). Ownership is applied as a wrapper after parsing the base type and its postfix constructors.
