# Generic parameter list

## Summary

`[TypeName, ...]` (same type parser is used for arguments, with declaration registration imposing parameter rules).

## Syntax shape

```text
[TypeName, ...]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Declare type parameters in square brackets before the header fields:

```mg
[T, U]
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Declare type variables in brackets before the ordinary header. Use each parameter as a type in fields, parameters, or the return type.

## Technical details

`src/parser.mg` (`parseTemplateArgs`). The parser reads this with the general type-argument parser; declaration registration then creates type-parameter declarations from the names. Function and struct header registration converts the parsed type names into scoped type-parameter declarations.
