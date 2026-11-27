# Return with a value

## Summary

`ret expr`.

## Syntax shape

```text
ret expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Return an expression compatible with the function’s declared return type:

```mg
ret total
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Return a value whose type matches the enclosing function’s declared return type.

## Technical details

`src/parser.mg` (`parseStatement`). The returned expression is stored on the return node and checked against the enclosing function return type. The AST stores this as `Expr.Return` with an expression in `src/shared/node_types.mg`.
