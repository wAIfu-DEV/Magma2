# Return without a value

## Summary

`ret`.

## Syntax shape

```text
ret
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a bare return in a function whose return type is `void`:

```mg
ret
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a bare return only when the enclosing function has no value to return (normally a `void` function).

## Technical details

`src/parser.mg` (`parseStatement`). The AST return node stores no expression when no value follows before newline or `..`. The AST stores this as `Expr.Return` without an expression in `src/shared/node_types.mg`.
