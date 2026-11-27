# Import/use declaration

## Summary

`use "path" [as] alias`; the alias is required and the `as` keyword is optional (`parseUseDecl`).

## Syntax shape

```text
use "path" [as] alias
```

The syntax line is schematic: replace placeholders such as `Type`, `expr`, and `body` with actual source types, expressions, and bodies.

## Example

Import a module and bind its required alias:

```mg
use "std:strings" strings
```

These are source fragments; any referenced types, functions, and variables must be declared in the surrounding module.

## How to use it

Import a module with a local alias, then qualify imported names through that alias. The alias is required; `as` is optional.

## Technical details

`src/parser.mg` (`parseUseDecl`). An alias is required. The optional `as` word is accepted before it, and the directive must end at a newline.
