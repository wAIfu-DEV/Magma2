# Composite declaration name

## Summary

`Owner.member`; used for method declarations and selected type/name contexts.

## Syntax shape

```text
Owner.member
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use a qualified name to select a member or declare an owner method:

```mg
Point.length
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use dot qualification for an owner member, especially method declarations. Each component after a dot must be a name.

## Technical details

`src/parser.mg` (`parseName`).
