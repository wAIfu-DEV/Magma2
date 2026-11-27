# Match statement

## Summary

`match expression as binding: arms`; `as binding` is required. Arms are `case Union.Variant: body` and optional `else: body`; close the match with `..` (`parseMatchStmt`).

## Syntax shape

```text
match expression as binding: arms
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Narrow a union through a binding, then handle its qualified variants:

```mg
match result as value:
case Result.Ok:
    consume(value)
case Result.Error:
    report(value)
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use match to branch on a narrowed union value. Bind it with `as`, handle qualified variants with `case`, and optionally add `else`.

## Technical details

`src/parser.mg` (`parseMatchStmt`). Match requires a narrowed binding and union-qualified case names; `..` ends the match. The AST stores this as `Stmt.Match` and `MatchCase` in `src/shared/node_types.mg`.
