# 8-bit character literals

## Summary

single-quoted, exactly one ASCII character or supported escape (`lexer.mg:lexLitChar`).

## Syntax shape

```text
'x'
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A single ASCII character can be written directly:

```mg
letter u8 = 'A'
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use single quotes for a single ASCII character, commonly where an 8-bit character is expected.

## Technical details

`src/lexer.mg` (`lexLitChar`). Exactly one ASCII character is required. Non-ASCII input is rejected for this delimiter. The lexer emits `TkType.LIT_CHAR8`; the parser represents it as `Literal.Char8`.
