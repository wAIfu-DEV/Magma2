# Line comments

## Summary

`# ...` to newline; newline remains a parser token.

## Syntax shape

```text
# comment text
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A line comment can document the next declaration:

```mg
# Number of retry attempts
retries u32 = 3
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `#` for a short note through the end of the current line.

## Technical details

`src/lexer.mg` (`run`, comment mode).
