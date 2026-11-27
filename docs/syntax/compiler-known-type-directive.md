# Compiler-known type directive

## Summary

`@compiler_known_type("name")`.

## Syntax shape

```text
@compiler_known_type("name")
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use this only for a type name supplied by a compiler-known mapping:

```mg
PlatformWord @compiler_known_type("platform_word")
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use only for a type that the compiler registers under the supplied string name. This is a compiler integration hook rather than a general alias.

## Technical details

`src/parser.mg` (`parseType`). This is the only supported compiler directive in type position; its argument must be a string literal.
