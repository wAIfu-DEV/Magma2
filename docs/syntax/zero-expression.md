# Zero expression

## Summary

`zero` produces a zero-initialized value of the type expected by its surrounding expression context. It is useful when an initializer must name every field but a field should receive its zero value.

## Syntax shape

```text
zero
```

## Example

```mg
f(.(x = value, y = zero))
```

Here `y` determines the type of `zero` from the corresponding struct field. Other typed contexts, such as a typed initializer, assignment, function argument, or return value, can provide its type too.

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

`zero` is a general expression, not specific to struct constructors. It requires an expected value type; using it without enough type context is a type error. It does not omit constructor fields or change default initialization behavior.

## Technical details

The parser stores the expression as `Expr.Zero` with its source position. Type checking supplies its type from the expected type. LLVM lowering emits `zeroinitializer` directly; it does not call or import `std:memory`.
