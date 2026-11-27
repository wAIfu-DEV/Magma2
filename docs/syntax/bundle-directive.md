# Bundle directive

## Summary

`bundle "file-path"` on its own line.

## Syntax shape

```text
bundle "file-path"
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Bundle a file relative to the source module:

```mg
bundle "assets/icon.png"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a bundle directive to include a file such as an asset with the module. Its path is resolved relative to the source file.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). The path is resolved relative to the current source file and registered as a bundle input.
