# Named type

## Summary

`Name` (including composite names where permitted).

## Syntax shape

```text
Name
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use the declared type name in typed positions:

```mg
Point
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a named type to refer to a declared type or built-in type. In contexts that allow it, dot-qualified names can select nested members.

## Technical details

`src/parser.mg` (`parseType`).
