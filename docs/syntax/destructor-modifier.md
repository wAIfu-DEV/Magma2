# Destructor modifier

## Summary

`destr` before a method declaration.

## Syntax shape

```text
destr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Mark a method that performs destruction for its owner type:

```mg
destr Buffer.free() void:
    ret
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use `destr` on an owner method that releases or finalizes its resource. Do not apply it to an ordinary function.

## Technical details

`src/parser.mg` (`parseGlobalStmt`): the destructor flag is attached to method functions; ordinary functions and variables reject it.. The parser records this flag on a method function; it rejects the modifier on ordinary functions and variables.
