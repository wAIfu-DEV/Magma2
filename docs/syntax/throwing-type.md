# Throwing type

## Summary

`!Type` (prefix).

## Syntax shape

```text
!Type
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Prefix a function return type with `!` to mark a throwing result:

```mg
read(path str) !File
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `!T` on a function return type to indicate that the call may produce an error in addition to `T`. Handle or propagate it with the language’s error forms.

## Technical details

`src/parser.mg` (`parseType`). The throwing marker wraps the parsed type and is distinct from the `throw` statement and `try` expression.
