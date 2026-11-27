# Module platform-pruning directive

## Summary

`@platform("platform", ...)`; controls whether the following declaration is parsed (`parseGlobalStmt`).

## Syntax shape

```text
@platform("platform", ...)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Place the directive immediately before the declaration it selects:

```mg
@platform("linux")
linuxSleep(ms u32) void:
    ret
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Place the directive directly before a declaration that only belongs on the selected platform. It controls parsing of that next declaration.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). This directive controls whether the following module-level declaration is parsed. Its arguments are string literals.
