# Prototype declaration

## Summary

`proto Name [(impl PrototypeTypes...)] (method(args...) ReturnType, ...)`; individual requirements may be prefixed `noctx`.

## Syntax shape

```text
proto Name [(impl PrototypeTypes...)] (method(args...) ReturnType, ...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Describe required methods once, then implement the prototype on concrete types:

```mg
proto Drawable (draw(canvas Canvas*) void)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a prototype to specify required methods shared by implementing types. Keep requirements nongeneric; declare generic ordinary methods separately.

## Technical details

`src/parser.mg` (`parseProtoDecl`). Prototype requirements are signatures; generic methods are rejected, and each method receives an implicit `this` receiver. The AST stores this as `GlobalStmt.Proto` in `src/shared/node_types.mg`.
