# Public modifier

## Summary

`pub` before a declaration or `use`.

## Syntax shape

```text
pub
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `pub` to make a declaration available to importing modules:

```mg
pub VERSION str = "1.0"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Put `pub` before a declaration or `use` line when other modules need access to it. Visibility is part of the declaration, so apply it where the declaration is written.

## Technical details

`src/parser.mg` (`parseGlobalStmt`, `parseUseDecl`): visibility is recorded in declaration metadata; `pub use` marks an import public.. The parser transfers this modifier into the declaration’s `isPublic` metadata. It also supports `pub use`.
