# Whitespace / line endings

## Summary

spaces, tabs, CR are skipped; LF emits a newline token.

## Syntax shape

```text
space / tab / CR whitespace; LF newline
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Separate statements with line breaks; indentation helps readers follow nesting:

```mg
if ready:
    ret 1
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use spaces or tabs for visual indentation. A single line break before `.` continues member access outside a delimited argument list; a blank line still separates expressions. Inside delimited argument lists, line breaks separate arguments.

## Technical details

`src/lexer.mg` (`isSpace`, `commitToken`, `run`).
