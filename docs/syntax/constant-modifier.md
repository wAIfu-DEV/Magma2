# Constant modifier

## Summary

`const name Type = expr` or `const name := expr`.

## Syntax shape

```text
const name Type = expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A constant must provide a value; its type may be explicit or inferred:

```mg
const MAX_RETRIES u32 = 5
const GREETING := "hello"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this for a value fixed at declaration time. Always provide an initializer; use `:=` when you want the initializer to determine the type.

## Technical details

`src/parser.mg` (`parseGlobalStmt`): constants require an initializer and cannot also use `global`.. Constants must have an initializer. They may use an explicit type or inferred assignment syntax.
