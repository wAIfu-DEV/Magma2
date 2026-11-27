# Inferred variable declaration

## Summary

`name := expr`.

## Syntax shape

```text
name := expr
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `:=` when the initializer should determine the variable type:

```mg
message := "ready"
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use inference for a local or module variable when its initializer clearly establishes the intended type. An initializer is required.

## Technical details

`src/parser.mg` (`parseGlobalStmt`): `:=` requires an initializer; its type is inferred during checking.. `:=` is a distinct token and the initializer is required so later checking can infer the declared type.
