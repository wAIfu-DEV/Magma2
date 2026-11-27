# No-context function type

## Summary

`noctx fn(ArgTypes...) ReturnType` (the parser also accepts `noctx` before the parenthesized form).

## Syntax shape

```text
noctx fn(ArgTypes...) ReturnType
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Prefix a function type with `noctx` when it has no implicit context:

```mg
clock noctx fn() u64
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `noctx` on a function type when a callback has no implicit context parameter; keep it attached to the function type itself.

## Technical details

`src/parser.mg` (`parseType`).
