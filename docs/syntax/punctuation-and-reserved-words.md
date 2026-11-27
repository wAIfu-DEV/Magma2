# Punctuation and reserved words

## Summary

The lexer recognizes the punctuation and keyword spellings below. A token being reserved does not mean it starts a standalone grammar production: its use depends on parser context. `zero` is a reserved keyword used as an expression.

## Syntax shape

```text
operators and delimiters are written using their punctuation spellings
reserved words are written using their keyword spellings
```

## Example

Examples of punctuation used as grammar delimiters and operators:

```mg
call(arg)
value := left + right
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use token spellings only in the grammar positions described by the individual sheets; reserved words cannot generally be reused as identifiers.

## Technical details

The authoritative spelling table is `src/shared/token_types.mg` (`KwTypeToRepr`). Punctuation tokenization and keyword recognition are implemented in `src/lexer.mg`; parser use sites are in `src/parser.mg`.
