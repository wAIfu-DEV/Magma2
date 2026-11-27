# Global variable modifier

## Summary

`global name Type [= expr]`.

## Syntax shape

```text
global name Type [= expr]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use global storage for a module-level variable that must persist:

```mg
global counter u64 = 0
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this only for mutable module-level storage whose lifetime must extend beyond a local scope. The compiler rejects combining it with `const`.

## Technical details

`src/parser.mg` (`parseGlobalStmt`): `global` marks module variable storage and is incompatible with `const`.. This marks a module variable as global storage; it cannot be combined with `const`.
