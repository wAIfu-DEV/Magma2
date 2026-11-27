# Body / block

## Summary

`: statement... ..`; nested bodies are parsed recursively. The closing `..` token also terminates a return/break/continue line without consuming the next statement.

## Syntax shape

```text
: statement... ..
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A body starts after `:` and ends at `..`:

```mg
run() void:
    prepare()
    execute()
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a body to group statements under a declaration or control-flow form. `..` closes it; indentation is only visual.

## Technical details

`src/parser.mg` (`parseBody`). The parser does not use indentation as a delimiter. `elif` and `else` can end a body so the conditional parser can handle them.
