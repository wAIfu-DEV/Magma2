# Embed expression

## Summary

`@embed("path")`.

## Syntax shape

```text
@embed("path")
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Embed a file relative to the current source file:

```mg
icon := @embed("assets/icon.png")
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `@embed` to load a source-relative file as a compile-time embedded value, commonly for assets or generated data.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The AST stores this as `Expr.Embed` in `src/shared/node_types.mg`.
