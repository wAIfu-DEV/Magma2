# With statement / scoped cleanup form

## Summary

`with local-statement then deferred-expression: body`; the parser lowers this to a scope containing the local, a deferred expression, and the body (`parseWithStmt`).

## Syntax shape

```text
with local-statement then deferred-expression: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Acquire a local resource, name its cleanup action, then run the body:

```mg
with file File = open(path) then file.close():
    process(file)
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `with` to keep acquisition, cleanup registration, and resource use together. The deferred expression is activated after the local statement.

## Technical details

`src/parser.mg` (`parseWithStmt`). The parser lowers this form to a scope containing the local statement, a deferred expression, and the body.
