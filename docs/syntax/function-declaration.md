# Function declaration

## Summary

`name(args...) ReturnType: body`; the absence of a newline between its header and return type distinguishes this from a struct declaration.

## Syntax shape

```text
name(args...) ReturnType: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A function has a typed header, return type, and colon body:

```mg
add(left i32, right i32) i32:
    ret left + right
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use functions for reusable behavior. Name every parameter and type it, state the return type, and put the body after `:`.

## Technical details

`src/parser.mg` (`parseHeader, parseBody`). The parser distinguishes a function from a struct declaration by whether a return type follows the header on the same logical line. The AST stores this as `GlobalStmt.Function` in `src/shared/node_types.mg`.
