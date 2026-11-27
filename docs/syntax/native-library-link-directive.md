# Native library link directive

## Summary

`link "library-name"` on its own line.

## Syntax shape

```text
link "library-name"
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Request a native library from the module build:

```mg
link "raylib"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Declare a native library dependency once at module scope. The library name is a string literal and must not be empty.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). The library string is added to the file’s native-library list for the link pipeline.
