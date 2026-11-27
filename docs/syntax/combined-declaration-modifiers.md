# Combined declaration modifiers

## Summary

supported modifier prefixes can be stacked where the target declaration permits them (`pub`, `global`, `const`, `noctx`, `destr`; parser validates combinations).

## Syntax shape

```text
pub const name Type = expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Put applicable modifiers before the declaration they modify:

```mg
pub const VERSION str = "1.0"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Place each modifier before the declaration. Use only combinations accepted for that declaration kind; for example, `global const` is rejected and `destr` is reserved for methods.

## Technical details

`src/parser.mg` (`parseGlobalStmt`): modifiers are accumulated before the declaration and validated when its kind is known..
