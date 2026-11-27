# Bounded predicates block

## Summary

`bounded predicate, ...: body`.

## Syntax shape

```text
bounded predicate, ...: body
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

State the safety relation that must hold for the body:

```mg
bounded index < length:
    use(data[index])
..
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use predicates to state the conditions that must hold while the body executes. Keep the conditions explicit and tied to the operations they protect.

## Technical details

`src/parser.mg` (`parseStatement`). Predicate expressions are comma-separated and must contain at least one predicate or pointer extent. The AST stores this as `Stmt.Bounded` with predicate expressions in `src/shared/node_types.mg`.
