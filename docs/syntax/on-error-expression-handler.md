# On-error expression handler

## Summary

`onerror expr`.

## Syntax shape

```text
onerror expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use an expression handler for compact error cleanup:

```mg
onerror release(resource)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Register a short expression to run when an error leaves the current scope.

## Technical details

`src/parser.mg` (`parseStatement`). The expression form registers an error handler for the current scope. The AST stores this as `Stmt.OnError` with an expression in `src/shared/node_types.mg`.
