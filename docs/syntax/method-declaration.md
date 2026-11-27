# Method declaration

## Summary

`Owner.method(args...) ReturnType: body`.

## Syntax shape

```text
Owner.method(args...) ReturnType: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A method is qualified by its owner type and can use the implicit `this` receiver:

```mg
Point.length() f64:
    ret this.x
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use an owner-qualified name to attach behavior to a type. The compiler provides an implicit `this` receiver; do not add a parameter with that name.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). The parser registers an implicit `this` receiver unless an explicit parameter already uses that name. The AST stores this as `GlobalStmt.Method` wrapping a function in `src/shared/node_types.mg`.
