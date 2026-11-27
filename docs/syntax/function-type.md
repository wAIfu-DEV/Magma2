# Function type

## Summary

`fn(ArgTypes...) ReturnType`.

## Syntax shape

```text
fn(ArgTypes...) ReturnType
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use `fn` to make a function type explicit:

```mg
callback fn(u32) bool
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a function type for callbacks or stored callable values. List argument types in order, followed by the return type.

## Technical details

`src/parser.mg` (`parseFunctionType`). The type node stores argument types, a return type, and the no-context flag.
