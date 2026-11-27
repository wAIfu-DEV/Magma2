# Variable declaration with explicit type

## Summary

`name Type [= expr]`.

## Syntax shape

```text
name Type [= expr]
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Declare a typed variable with or without an initial value:

```mg
count u32 = 0
nextCount u32
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Prefer an explicit type when the initializer is absent or when the declared interface should be visible at the declaration site.

## Technical details

`src/parser.mg` (`parseGlobalStmt`, `parseVariableStatement`): the type is parsed before an optional `=` initializer; omitting it leaves a declaration without assignment.. The type is parsed before the optional `=` initializer. Without an initializer, this is a declaration without assignment. The AST stores this as `GlobalStmt.Variable` in `src/shared/node_types.mg`.
