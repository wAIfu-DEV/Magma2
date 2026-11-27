# Combined type qualifiers

## Summary

`$`, `!`, and `noctx` prefixes can be consumed in sequence; ownership and throwing wrappers are applied around the parsed type.

## Syntax shape

```text
!$Type
```

Here `Type` is a type placeholder. `noctx` can qualify only a function type; `$` and `!` are ownership and throwing type prefixes.

## Example

Qualifiers can wrap a type; `noctx` applies only when the type is a function type:

```mg
!$File
noctx fn(u32) void
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Combine ownership and throwing prefixes only when the resulting type matches the function or value contract. `noctx` is specifically for function types.

## Technical details

`src/parser.mg` (`parseType`).
