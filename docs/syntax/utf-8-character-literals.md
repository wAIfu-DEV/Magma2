# UTF-8 character literals

## Summary

backtick-quoted, exactly one character including non-ASCII (`lexer.mg:lexLitChar`).

## Syntax shape

```text
`λ`
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a backtick literal for a single non-ASCII code point:

```mg
symbol u32 = `λ`
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use backticks for one Unicode character, especially when the character is outside ASCII.

## Technical details

`src/lexer.mg` (`lexLitChar`). Exactly one Unicode code point is required; the character is encoded as UTF-8 in the token value. The lexer emits `TkType.LIT_CHAR32`; the parser represents it as `Literal.Char32`.
