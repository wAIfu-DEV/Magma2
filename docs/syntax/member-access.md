# Member access

## Summary

`owner.member`.

## Syntax shape

```text
owner.member
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Select a field or method from an owner expression:

```mg
point.x
```

Member and method chains may continue after one newline when the next line starts with a dot:

```mg
value.doSomething()
  .processOutput()
  .cleanup()
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use dot access to select a field or method from an owner expression. It binds more tightly than infix operators. Outside a delimited argument list, one newline immediately before `.` continues the expression; a blank line ends it. Inside delimited argument lists, newlines separate arguments, so put each member chain on one line.

## Technical details

`src/parser.mg` (`parseExpression`, `parseCallArgs`). The member after `.` must be a name. Member access binds more tightly than infix operators. A single newline before `.` continues an expression unless parsing a delimited argument list; two newlines terminate the expression. The AST stores this as `Expr.MemberAccess` in `src/shared/node_types.mg`.
