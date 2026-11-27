# Simple name

## Summary

`name`.

## Syntax shape

```text
name
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A simple name refers to one declaration:

```mg
counter
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a simple name for one identifier. Use a qualified/composite name only where that grammar position supports it.

## Technical details

`src/parser.mg` (`parseNameSimple`).
