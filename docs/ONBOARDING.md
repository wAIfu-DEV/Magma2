# Welcome to Magma

This guide takes you from an empty source file to the language's main ideas: typed values, functions, control flow, errors, and resource ownership. It is written for someone new to Magma. You can read it top to bottom, or jump to the topic you want to try.

## Your first program

Create a file named `hello.mg`:

```magma
mod main

use "std:io" as io

pub main() !void:
    greeting := "Hello from Magma!"
    try io.printLn(greeting)
    ret
..
```

This small program introduces several common parts of Magma:

- `mod main` names the module.
- `use "std:io" as io` brings in the standard I/O module under the name `io`.
- `pub` makes `main` available as the program entry point.
- `greeting := ...` creates a local and asks Magma to infer its type.
- `!void` says that `main` can return an error and has no ordinary return value.
- `try` handles the error path from `io.printLn` by passing it back to the caller.
- `:` opens the function body and `..` closes it.

If Magma is available as the `magma` command, compile and run the file with:

```sh
magma --run hello.mg
```

The output should be:

```text
Hello from Magma!
```

## A quick tour of the syntax

The snippets in this section are small pieces to add to your program. Unless a
snippet shows a type or function declaration, place its statements inside a
function. Snippets that use `io` assume the `std:io` import from the first
program.

### Values and variables

You can write a type explicitly or let Magma infer it:

```magma
example() void:
    count u64 = 3
    message := "three items"

    count = count + 1
..
```

Types follow the variable name. `:=` declares a new inferred local, while `=` updates an existing one. Common types include `bool`, `str`, signed and unsigned integers such as `i32` and `u64`, and floating-point values such as `f64`.

### Functions

Functions have typed parameters and a return type:

```magma
square(value u64) u64:
    ret value * value
..
```

Call it from another function:

```magma
example() void:
    answer := square(6)
..
```

Use `void` when a function has no ordinary return value. Functions that may fail prefix the return type with `!`, as in `!void` or `!u64`.

### Conditions and loops

Conditions use `if`, `elif`, and `else`. A colon starts each body; `..` closes the complete conditional:

```magma
report(count u64) !void:
    if count == 0:
        try io.printLn("empty")
    else:
        try io.printLn("has items")
    ..
    ret
..
```

Use `loop` for a condition-controlled loop and `for` for a counted loop:

```magma
repeat() !void:
    for i := 0 to 5:
        # Runs with i equal to 0, 1, 2, 3, and 4.
        try io.printLn("one step")
    ..
    ret
..
```

The upper bound in a `for` loop is exclusive. `break` leaves a loop and `continue` starts its next iteration.

For a condition-controlled loop, use `loop`:

```magma
countdown() void:
    count u64 = 3
    loop count > 0:
        count = count - 1
    ..
..
```

### Structs and methods

Structs group named fields together. Methods are declared with the struct name before the method name; `this` refers to the receiver:

```magma
Counter(value u64)

Counter.increment() void:
    this.value = this.value + 1
..
```

Use the type from a function:

```magma
example() void:
    counter := Counter(value=0)
    counter.increment()
..
```

Generic functions and structs use square brackets for type parameters and arguments. For example, a container can be written `Array[u8]` or `Array[str]`.

### Errors and `try`

An operation that can fail advertises that in its return type. For example, `io.printLn` returns `!u64`: it can produce a byte count or an error. In a function whose return type is also throwing, `try` is a concise way to pass a failure to the caller:

```magma
sayHello() !void:
    try io.printLn("Hello!")
    ret
..
```

You can also inspect an error yourself. A call can be received as a value and an error, then checked with `.ok()` or `.nok()`. Use `throw` when your function needs to return an error:

```magma
checkCount(count u64) !void:
    if count == 0:
        throw "count must be positive"
    ..
    ret
..
```

### Slices and arrays

`T[]` is a slice of values with element type `T`; `T*` is a pointer to `T`. A local array expression creates convenient storage for a fixed number of elements:

```magma
sumValues() u64:
    values := [3]u64(10, 20, 30)
    total u64 = 0

    for i u64 = 0 to values.count():
        total = total + values[i]
    ..
    ret total
..
```

The standard library has array, slice, vector, and iterator modules for common collection tasks. Start with those when you need a collection; direct pointers and explicit bounds are useful when you need lower-level control.

## Let Magma help with cleanup

Some values own resources, such as allocated strings, files, and network handles. Magma marks ownership in types and lets you register cleanup with `defer`:

```magma
use "std:io" as io
use "std:strings" as strings

makeMessage() !void:
    message := try strings.copy("A message with owned storage")
    defer message.free()

    try io.printLn(message)
..
```

Here, `strings.copy` returns an owned string. `defer` schedules `free()` when the current body exits, including when a later `try` propagates an error. A parameter written `$T` accepts ownership; an unmarked parameter ordinarily borrows the value for the call. When transferring an existing owned local, write `move`:

```magma
consume(message $str) void:
    message.free()
..

message := try strings.copy("transfer me")
consume(move message)
```

Types can provide a `destr` method for resource cleanup. The standard library uses this pattern for many resources. Look at the type's API comments for the expected cleanup method and ownership behavior.

## A few helpful language patterns

### Use `match` for union values

Unions represent one of several named variants. A `match` can narrow a union to a particular variant and expose that variant's fields. The JSON module provides a substantial example: `std/json.mg` defines `Value` variants such as `Null`, `Bool`, `String`, `Array`, and `Object`, then matches on them when serializing.

### Use prototypes for shared behavior

A `proto` declares a set of methods that an implementation type provides. This is useful when different types should be used through the same API. The standard library's `std/reader.mg`, `std/writer.mg`, and `std/allocator.mg` are good places to see this pattern.

### Keep low-level operations explicit

Magma supports pointers, `addrof`, casts, and external functions for systems-level work. Ordinary slice indexing and common library operations are a comfortable place to start. As you move to raw pointers or native interfaces, follow the library's bounds and `unsafe` conventions closely.

## Where to explore next

- **Input and output:** `std/io.mg`, `std/reader.mg`, and `std/writer.mg`
- **Strings and bytes:** `std/strings.mg`, `std/bytes.mg`, and `std/utf8.mg`
- **Collections:** `std/array.mg`, `std/vector.mg`, `std/list.mg`, and `std/hash_map.mg`
- **Errors:** `std/errors.mg` and `std/tests/errors.mg`
- **Ownership examples:** `std/tests/strings.mg`, `std/tests/file.mg`, and `std/tests/thread.mg`
- **Prototypes and interfaces:** `std/allocator.mg`, `std/reader.mg`, and `std/writer.mg`
- **Unions and matching:** `std/json.mg`

## A small practice project

Try making a tiny counter program:

1. Declare a `Counter` struct with a `value u64` field.
2. Add an `increment()` method that updates `this.value`.
3. Create a counter initialized to zero.
4. Use a `for` loop to increment it several times.
5. Print a completion message with `io.printLn`.

This exercise brings together modules, structs, methods, local values, loops, and standard-library output. Once it feels familiar, change the program to read input or to store values in a standard-library collection.
