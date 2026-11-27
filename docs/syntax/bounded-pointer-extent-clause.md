# Bounded pointer/extent clause

## Summary

`bounded pointer by extent, ...: body`; may be combined with predicates.

## Syntax shape

```text
bounded pointer by extent, ...: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Tie a pointer to an expression that describes its element extent:

```mg
bounded data by length:
    consume(data, length)
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Associate each pointer with an expression giving its valid extent, then keep accesses within the bounded body.

## Technical details

`src/parser.mg` (`parseStatement`). Each pointer extent is written as `pointer by extent`; clauses can be mixed with predicate expressions. The AST stores this as `Stmt.Bounded` with pointer and extent arrays in `src/shared/node_types.mg`.
