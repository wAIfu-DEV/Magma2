# Module-level inline LLVM

## Summary

`llvm "LLVM text"` on its own line.

## Syntax shape

```text
llvm "LLVM text"
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use this declaration form to provide a line of LLVM IR:

```mg
llvm "declare void @abort()"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this only when module-level LLVM text is required. Keep the entire payload in one string literal on its own line.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). The LLVM text must be one string literal and the declaration ends at the newline.
