# Statement-level inline LLVM

## Summary

`llvm "LLVM text"` on its own line.

## Syntax shape

```text
llvm "LLVM text"
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Provide one LLVM text string as a standalone statement:

```mg
llvm "call void @abort()"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use inline LLVM as a last-resort low-level statement. The text is passed as one line string payload.

## Technical details

`src/parser.mg` (`parseStatement`). The LLVM text must be one string literal and the statement ends at the newline.
