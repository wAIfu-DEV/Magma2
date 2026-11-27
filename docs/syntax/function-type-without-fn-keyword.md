# Function type without `fn` keyword

## Summary

`(ArgTypes...) ReturnType`.

## Syntax shape

```text
(ArgumentTypes...) ReturnType
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

The parenthesized form is a shorter spelling of a function type:

```mg
callback (u32) bool
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use the parenthesized shorthand where a function type is expected and the surrounding declaration makes the type position clear.

## Technical details

`src/parser.mg` (`parseFunctionType`).
