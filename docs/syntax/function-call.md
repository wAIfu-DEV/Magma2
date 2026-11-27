# Function call

## Summary

`callee(args...)`.

## Syntax shape

```text
callee(args...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Call a function by placing arguments after its name:

```mg
add(2, 3)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Call a named function, callable value, or member by placing its value arguments in parentheses.

## Technical details

`src/parser.mg` (`parseExpression, parseCallArgs`). Calls are initially parsed as indirect calls; later name resolution classifies direct functions, methods, and constructors. The AST stores this as initially `Expr.IndirectCall`; call classification occurs later in `src/shared/node_types.mg`.
