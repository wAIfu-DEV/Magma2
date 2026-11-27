# Comma-separated lists

## Summary

the parser uses commas and, in several lists, newlines as separators; the accepted list contexts are call args, type args, headers, prototypes, unions, enums, and bounded clauses.

## Syntax shape

```text
item, item
item
item
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use commas between same-line items; newlines are accepted in supported list forms:

```mg
first,
second,
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Separate list elements with one comma. Newlines are also accepted in the list forms documented here; avoid consecutive commas.

## Technical details

`src/parser.mg` (`consumeListSeparators`).
