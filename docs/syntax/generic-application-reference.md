# Generic application/reference

## Summary

`callee[TypeArgs...]` in the parser's generic-reference context.

## Syntax shape

```text
callee[TypeArgs...]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A generic reference can pass a specialized function as a value:

```mg
callbacks.pushRight[Item, Allocator](item, allocator)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use generic application to refer to a specialized generic value where the parser recognizes a type-argument reference; distinguish it from indexing.

## Technical details

`src/parser.mg` (`parseExpression, parseTemplateArgs`). The parser distinguishes a generic call from indexing by the closing bracket’s following token. Generic reference parsing has a narrower recognition condition than generic calls. The AST stores this as `Expr.GenericApply` in `src/shared/node_types.mg`.
