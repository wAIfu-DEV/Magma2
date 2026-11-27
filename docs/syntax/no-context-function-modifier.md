# No-context function modifier

## Summary

`noctx` before a function declaration; also a function-type modifier.

## Syntax shape

```text
noctx
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Mark a function when it should not receive the implicit context:

```mg
noctx currentTime() u64:
    ret 0
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this for functions that do not receive the implicit context parameter. It applies to supported function declarations, not variables or structs.

## Technical details

`src/parser.mg` (`parseGlobalStmt`): the no-context flag is stored on supported function declarations; variables and structs reject it.. This flag is stored on function declarations and affects function type construction. It is not valid on variables or struct declarations.
