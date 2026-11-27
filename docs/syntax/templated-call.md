# Templated call

## Summary

`callee[TypeArgs...](args...)`.

## Syntax shape

```text
callee[TypeArgs...](args...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Supply type arguments before the call’s value arguments:

```mg
makePair[i32, str](1, "one")
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a templated call when type inference cannot select the desired specialization or when the type arguments are part of the API.

## Technical details

`src/parser.mg` (`parseExpression, parseTemplateArgs`). Type arguments are parsed before the ordinary call argument list and stored separately on the call node. The AST stores this as `Expr.TemplatedIndirectCall` before call resolution in `src/shared/node_types.mg`.
