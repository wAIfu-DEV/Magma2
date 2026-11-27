# Header argument list

## Summary

`(name Type, ...)`; comma or newline separators and trailing separator accepted.

## Syntax shape

```text
(name Type, ...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Headers list named, typed parameters or fields:

```mg
(x f64, y f64)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

List named typed fields or parameters in declaration order. Use commas for readability; newlines may separate entries too.

## Technical details

`src/parser.mg` (`parseTypedArgList`). Each entry is a named typed field; the parser accepts comma or newline separators and trailing separators.
