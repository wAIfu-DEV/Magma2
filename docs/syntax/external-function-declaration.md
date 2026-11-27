# External function declaration

## Summary

`ext languageName externalSymbol(args...) ReturnType`; optionally prefixed `pub` or `noctx`.

## Syntax shape

```text
ext languageName externalSymbol(args...) ReturnType
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Map a source-level declaration to an external symbol:

```mg
ext puts puts(text str) i32
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this declaration for a function implemented outside Magma. The first name is the source API name and the second is the external symbol name.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). The external symbol name is kept separately from the source-level function name in the declaration node. The AST stores this as `GlobalStmt.ExternalFunction` in `src/shared/node_types.mg`.
