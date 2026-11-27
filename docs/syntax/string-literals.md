# String literals

## Summary

double-quoted, may span source newlines; backslash escapes include `\a`, `\b`, `\f`, `\n`, `\r`, `\t`, `\v`, `\\`, `\'`, `\"` (and escaped backtick handling in character literals) (`lexer.mg:toggleStringMode`, `escapeChar`).

## Syntax shape

```text
"text"
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a string literal as a value, for example as a function argument:

```mg
print("hello\n")
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use double quotes for text. Use escapes for control characters and quote characters that would otherwise end the literal.

## Technical details

`src/lexer.mg` (`toggleStringMode`, `escapeChar`, `run`). Supported escapes are `\a`, `\b`, `\f`, `\n`, `\r`, `\t`, `\v`, `\\`, `\'`, and `\"`. The lexer decodes these when it builds the string token; multiline strings are accepted. The parser stores the decoded string payload in `Literal.String` under an `Expr.Literal` node.
