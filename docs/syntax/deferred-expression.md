# Deferred expression

## Summary

`defer expr`.

## Syntax shape

```text
defer expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Schedule a cleanup call after the current scope finishes:

```mg
defer file.close()
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Register a short cleanup expression that should run when the current scope exits.

## Technical details

`src/parser.mg` (`parseStatement`). A deferred expression is registered for execution when the current scope exits. The AST stores this as `Stmt.Defer` with an expression in `src/shared/node_types.mg`.
