# Multiline comments

## Summary

`## ... ##`; newlines inside remain parser tokens (`lexer.mg:run`).

## Syntax shape

```text
## comment text ##
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a paired delimiter to comment out or explain several lines:

```mg
##
Temporary workaround
remove after backend update
##
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use paired `##` delimiters for a comment spanning lines; source newlines remain visible to the parser.

## Technical details

`src/lexer.mg` (`run`, multiline-comment mode).
