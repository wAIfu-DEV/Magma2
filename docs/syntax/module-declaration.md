# Module declaration

## Summary

`mod name` (only one per parsed module; inspect `parseGlobalStmt`).

## Syntax shape

```text
mod name
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A module declaration normally appears at the top of a source file:

```mg
mod example
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Put the module declaration near the top of the file and make its name match the file’s module name.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). At most one module declaration is accepted, and its name is checked against the file module name.
