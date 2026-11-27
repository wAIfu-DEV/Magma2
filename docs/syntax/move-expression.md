# Move expression

## Summary

`move expr`.

## Syntax shape

```text
move expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Move a value when ownership should transfer to the destination:

```mg
destination := move source
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Move when ownership should transfer instead of copying. After a move, do not use the source as though it still owns the resource.

## Technical details

`src/parser.mg` (`parseExprPrefix`). Move is represented as a distinct expression node so ownership analysis can track transfer. The AST stores this as `Expr.Move` in `src/shared/node_types.mg`.
