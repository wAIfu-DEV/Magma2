# Call argument list

## Summary

`(expr, ...)`; newline separators and trailing separator accepted.

## Syntax shape

```text
(expr, ...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Pass values in the same order as the callee’s parameter list:

```mg
(left, right)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Pass one expression per parameter, in declaration order. Use commas or newlines to separate arguments. A dot at the start of the next line starts a new argument expression; member chains in an argument must stay on one line.

## Technical details

`src/parser.mg` (`parseCallArgs`). Each entry is parsed as a full expression; comma and newline separators and a trailing separator are accepted. Newline member continuation is disabled inside this delimited argument list so leading `.Variant` can begin a separate contextual enum argument.
