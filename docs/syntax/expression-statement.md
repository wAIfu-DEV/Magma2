# Expression statement

## Summary

`expr`.

## Syntax shape

```text
expression
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

A call or other value expression can stand alone as a statement:

```mg
logMessage("started")
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use a bare expression statement for an operation performed for its effects, such as a call or assignment.

## Technical details

`src/parser.mg` (`parseStatement`, `parseExpression`). Expressions are parsed with the Pratt parser. A single newline immediately followed by `.` continues member access outside delimited argument lists; other newlines, commas, and colons terminate the current expression. The AST stores this as `Stmt.Expression` in `src/shared/node_types.mg`.
