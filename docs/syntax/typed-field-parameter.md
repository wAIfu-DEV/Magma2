# Typed field / parameter

## Summary

`name Type`.

## Syntax shape

```text
name Type
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Give each field or parameter a name followed by its type:

```mg
width u32
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Give each argument or field a clear name and type so callers and constructors have an explicit interface.

## Technical details

`src/parser.mg` (`parseVarDefTyped`): a field consists of a simple name, parsed type, and optional bounded-count annotation..
