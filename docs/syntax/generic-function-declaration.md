# Generic function declaration

## Summary

`name[TypeParams...](args...) ReturnType: body`.

## Syntax shape

```text
name[TypeParams...](args...) ReturnType: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a type parameter when the function works with several concrete types:

```mg
identity[T](value T) T:
    ret value
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a type parameter when the implementation is independent of a concrete type. Declare the parameter in brackets and use it in the typed header or return type.

## Technical details

`src/parser.mg` (`parseHeader, parseTemplateArgs`). Type parameters are parsed in brackets and registered in the function header scope before argument and return types are resolved. The AST stores this as `GlobalStmt.Function` plus a templated header in `src/shared/node_types.mg`.
