# Hexadecimal numeric literals

## Summary

`0x...` / `0X...` with hex digits; token representation includes the language's synthetic `u` prefix (`lexer.mg:toggleNumberMode`, `lexer.mg:lexHexNum`).

## Syntax shape

```text
0x2a or 0X2A
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A hexadecimal spelling can initialize an integer value:

```mg
mask u32 = 0x00ff
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a hexadecimal spelling when the value is clearer in base 16; use only hexadecimal digits after the prefix.

## Technical details

`src/lexer.mg` (`toggleNumberMode`, `lexHexNum`). The lexer accepts `0x` / `0X` followed by hexadecimal digits. Its internal token representation adds a synthetic `u` prefix. The parser stores the numeric token as a number literal; the lexer’s synthetic prefix is part of the token representation, not source text.
