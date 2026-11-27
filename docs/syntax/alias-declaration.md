# Alias declaration

## Summary

`alias Name = Type`.

## Syntax shape

```text
alias Name = Type
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Give a type a shorter or domain-specific name:

```mg
alias UserId = u64
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use an alias to shorten a type name or expose a domain-specific name. The right side must be a type.

## Technical details

`src/parser.mg` (`parseGlobalStmt`). The alias target is parsed as a type and stored in `GlobalStmt.Alias`. The AST stores this as `GlobalStmt.Alias` in `src/shared/node_types.mg`.
