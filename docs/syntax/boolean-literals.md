# Boolean literals

## Summary

`true`, `false`.

## Syntax shape

```text
true or false
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use the boolean keywords in conditions and boolean initializers:

```mg
enabled bool = true
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this spelling in the source position accepted by the surrounding grammar.

## Technical details

`src/shared/token_types.mg` and `src/parser.mg` (`parseExprPrefix`). The literal token is represented by the parser as a boolean-valued `Expr.Literal` node.
