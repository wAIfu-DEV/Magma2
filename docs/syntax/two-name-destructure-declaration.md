# Two-name destructure declaration

## Summary

`valueName, errorName := expression` (`parseDestructureStatement`).

## Syntax shape

```text
valueName, errorName := expression
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Bind the value and error results of a call in one statement:

```mg
value, err := readFile(path)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use this form for calls whose result is split into value and error bindings. The parser requires `:=` for this form.

## Technical details

`src/parser.mg` (`parseDestructureStatement`). The AST stores this as `Expr.VarDefAssignDestructure` in `src/shared/node_types.mg`.
