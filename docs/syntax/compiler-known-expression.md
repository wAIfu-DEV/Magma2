# Compiler-known expression

## Summary

`@compiler_known("name")`.

## Syntax shape

```text
@compiler_known("name")
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Request a compiler-known constant by its registered name:

```mg
version := @compiler_known("version")
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use only with a compiler-known constant name. It is intended for compiler-provided values, not arbitrary string lookup.

## Technical details

`src/parser.mg` (`parseExprPrefix`). The AST stores this as `Expr.CompilerKnown` in `src/shared/node_types.mg`.
