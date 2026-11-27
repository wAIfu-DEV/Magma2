# Inline LLVM expression

## Summary

`@llvm("operation", operand..., ResultType)`; the final argument is a type.

## Syntax shape

```text
@llvm("operation", operand..., ResultType)
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Use an inline LLVM expression when an operation is not expressible in Magma:

```mg
value := @llvm("add", left, right, i32)
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Use an inline LLVM expression when a low-level operation must produce a typed Magma value. The final argument must be the result type.

## Technical details

`src/parser.mg` (`parseExprPrefix`). Operand expressions are a delimited argument list, so a newline before `.` separates arguments and does not continue member access. The AST stores this as `Expr.InlineLLVM` in `src/shared/node_types.mg`.
