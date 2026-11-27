# Decimal numeric literals

## Summary

digit-started numeric text, optional leading `-`, decimal point; lexer accepts digits, `.` and `-` in a number token. Exponent notation is not a distinct lexer form (`lexer.mg:toggleNumberMode`, `lexer.mg:run`).

## Syntax shape

```text
42 or -3.5
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

These literal tokens can be used in an expression or initializer:

```mg
count i32 = 42
ratio f64 = -3.5
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use decimal spelling for ordinary integer and fractional values. Keep the literal within the range and type required by its context.

## Technical details

`src/lexer.mg` (`toggleNumberMode`, `run`). The scanner accepts decimal digits, a leading minus when immediately followed by a digit, and periods in the numeric token. Exponent syntax is not separately recognized. The source spelling is retained as a numeric literal payload; type and range checking occur after parsing.
