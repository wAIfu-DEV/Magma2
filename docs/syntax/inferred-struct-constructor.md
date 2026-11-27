# Inferred struct constructor

## Summary

`.(field = expression, ...)`; the struct type is taken from the expected type.

## Syntax shape

```text
.(field = expression, ...)
```

Only named field initializers are accepted. The constructor must initialize every field exactly once, using the same validation as a named struct constructor.

## Example

An explicit variable type provides the expected struct type:

```mg
value Point = .(x = 0.0, y = 0.0)
```

A function parameter can provide the type too:

```mg
draw(point Point) void:
..

draw(.(x = 1.0, y = 2.0))
```

These are source fragments; `Point` and its fields must be declared in the surrounding module.

## How to use it

Use `.(...)` when the surrounding context determines a struct type. The expected type may come from a typed initializer, assignment, return type, or function parameter. A generic struct is supported when its type arguments are known from context. Without enough type information, use the ordinary named constructor, such as `Point(x = 0.0, y = 0.0)`.

Nested field values are checked against their declared field types, so contextual enum variants can be used inside a constructor when the field type is an enum.

## Technical details

`src/parser.mg` (`parseExprPrefix`) parses the form into `Expr.InferredStructConstructor`. `src/link_checker.mg` resolves it from an expected struct type and reuses named struct field validation. `src/llvm_lowering.mg` uses the existing struct constructor lowering.
