# Generic-owner method declaration

## Summary

`Owner[TypeArgs...].method(args...) ReturnType: body`.

## Syntax shape

```text
Owner[TypeArgs...].method(args...) ReturnType: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Qualify a method with the instantiated generic owner type:

```mg
Vector[T].first() T:
    ret this.data[0]
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this spelling for methods on generic owner types. State owner type arguments before `.method`; the owner’s type parameters are in scope for the method.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). The AST stores this as `GlobalStmt.Method` with a templated owner in `src/shared/node_types.mg`.
