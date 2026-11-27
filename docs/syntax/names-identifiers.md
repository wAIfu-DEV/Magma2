# Names / identifiers

## Summary

ASCII letters and digits plus `_` after an initial letter or `_`; keyword spellings are tokenized separately. Some name positions accept the keyword `to` as a name (`parseName`, `isNameToken`).

## Syntax shape

```text
name
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

In a declaration, the identifier names the value or type:

```mg
answer i32 = 42
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Choose descriptive names and avoid reserved words, except `to` where the parser explicitly accepts it as a name.

## Technical details

`src/lexer.mg` (`run`, `pushTokenBuff`); keywords are looked up in `src/shared/token_types.mg`.
