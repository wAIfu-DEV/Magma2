# Template type-argument list

## Summary

`[Type, ...]`.

## Syntax shape

```text
[Type, ...]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Supply concrete types in the same bracketed form:

```mg
[u8, u64]
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Supply concrete types in the declaration’s parameter order. Use nested type forms where needed.

## Technical details

`src/parser.mg` (`parseTemplateArgs`).
