mod flag
# Declarative typed command-line option parsing without shell interpretation.

use "std:allocator" as allocator
use "std:array" as array
use "std:strings" as strings
use "std:slices" as slices
use "std:strconv" as strconv
use "std:errors" as errors
use "std:cast" as cast
use "std:writer" as writer
use "std:builder" as builder

const KIND_BOOL u8 = 1
const KIND_STRING u8 = 2
const KIND_UNSIGNED u8 = 3
const KIND_INTEGER u8 = 4
const KIND_STRINGS u8 = 5
const KIND_UNSIGNEDS u8 = 6
const KIND_INTEGERS u8 = 7

Definition(
    name str
    short u8
    help str
    kind u8
    destination ptr
    seen bool
)

pub Parser(
    allocator allocator.Allocator
    program str
    definitions array.Array[Definition]
)

pub Result(
    allocator allocator.Allocator
    values array.Array[str]
)

pub new(a allocator.Allocator, program str) !$Parser:
    defs := try array.new[Definition](a)
    ret Parser(allocator=a, program=program, definitions=move defs)
..

Parser.add(name str, short u8, help str, kind u8, destination ptr) !void:
    if name.countBytes() == 0:
        throw errors.invalidArgument("flag name cannot be empty")
    ..
    defs := this.definitions.view()
    for i u64 = 0 to this.definitions.count():
        if strings.compare(defs[i].name, name) || (short != 0 && defs[i].short == short):
            throw errors.invalidArgument("duplicate flag name")
        ..
    ..
    try this.definitions.pushRight(this.allocator, Definition(name=name, short=short, help=help, kind=kind, destination=destination, seen=false))
..

Parser.boolean(name str, short u8, destination bool*, help str) !void:
    try this.add(name, short, help, KIND_BOOL, destination)
..
Parser.string(name str, short u8, destination str*, help str) !void:
    try this.add(name, short, help, KIND_STRING, destination)
..
Parser.unsigned(name str, short u8, destination u64*, help str) !void:
    try this.add(name, short, help, KIND_UNSIGNED, destination)
..
Parser.integer(name str, short u8, destination i64*, help str) !void:
    try this.add(name, short, help, KIND_INTEGER, destination)
..
Parser.strings(name str, short u8, destination array.Array[str]*, help str) !void:
    try this.add(name, short, help, KIND_STRINGS, destination)
..
Parser.unsigneds(name str, short u8, destination array.Array[u64]*, help str) !void:
    try this.add(name, short, help, KIND_UNSIGNEDS, destination)
..
Parser.integers(name str, short u8, destination array.Array[i64]*, help str) !void:
    try this.add(name, short, help, KIND_INTEGERS, destination)
..

findLong(parser Parser*, name str) !Definition*:
    defs := parser.definitions.view()
    for i u64 = 0 to parser.definitions.count():
        if strings.compare(defs[i].name, name): ret addrof defs[i] ..
    ..
    throw errors.invalidArgument("unknown command-line option")
..

findShort(parser Parser*, name u8) !Definition*:
    defs := parser.definitions.view()
    for i u64 = 0 to parser.definitions.count():
        if defs[i].short == name: ret addrof defs[i] ..
    ..
    throw errors.invalidArgument("unknown command-line option")
..

parseInteger(value str) !i64:
    if value.countBytes() == 0: throw errors.invalidArgument("empty signed integer") ..
    negative := strings.byteAt(value, 0) == 45
    start u64 = 0
    if negative: start = 1 ..
    if start == value.countBytes(): throw errors.invalidArgument("invalid signed integer") ..
    part := strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(value)) + start), value.countBytes() - start)
    magnitude := try strconv.parseUint(part)
    if negative:
        if magnitude > 9223372036854775808: throw errors.wouldOverflow("signed integer overflow") ..
        if magnitude == 9223372036854775808: ret -9223372036854775807 - 1 ..
        ret 0 - cast.utoi(magnitude)
    ..
    if magnitude > 9223372036854775807: throw errors.wouldOverflow("signed integer overflow") ..
    ret cast.utoi(magnitude)
..

appendBorrowed(values array.Array[str]*, a allocator.Allocator, value str) !void:
    index := try values.expandRight(a)
    items := values.view()
    # expandRight returns the newly initialized final slot.
    bounded index < items.count():
        items[index] = value
    ..
..

apply(parser Parser*, def Definition*, value str, hasValue bool) !void:
    # SAFETY: Definition.kind records the concrete type of destination, which
    # was captured from the matching typed registration API and remains live
    # for the parser's use.
    unsafe:
    if def.kind != KIND_STRINGS && def.kind != KIND_UNSIGNEDS && def.kind != KIND_INTEGERS && def.seen:
        throw errors.invalidArgument("duplicate command-line option")
    ..
    if def.kind == KIND_BOOL:
        if hasValue: throw errors.invalidArgument("boolean option does not take a value") ..
        target bool* = def.destination
        *target = true
    else:
        if hasValue == false: throw errors.invalidArgument("command-line option is missing its value") ..
        if def.kind == KIND_STRING:
            target str* = def.destination
            *target = value
        elif def.kind == KIND_UNSIGNED:
            target u64* = def.destination
            *target = try strconv.parseUint(value)
        elif def.kind == KIND_INTEGER:
            target i64* = def.destination
            *target = try parseInteger(value)
        elif def.kind == KIND_STRINGS:
            target array.Array[str]* = def.destination
            try appendBorrowed(target, parser.allocator, value)
        elif def.kind == KIND_UNSIGNEDS:
            target array.Array[u64]* = def.destination
            try target.pushRight(parser.allocator, try strconv.parseUint(value))
        else:
            target array.Array[i64]* = def.destination
            try target.pushRight(parser.allocator, try parseInteger(value))
        ..
    ..
      def.seen = true
    ..
..

Parser.parse(arguments str[]) !$Result:
    defs := this.definitions.view()
    for d u64 = 0 to this.definitions.count():
        defs[d].seen = false
    ..
    positional := try array.new[str](this.allocator)
    onerror positional.free(this.allocator, none)
    i u64 = 0
    options bool = true
    loop i < slices.count(arguments):
        arg := arguments[i]
        if options && strings.compare(arg, "--"):
            options = false
        elif options && arg.countBytes() > 2 && strings.byteAt(arg, 0) == 45 && strings.byteAt(arg, 1) == 45:
            body := strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(arg)) + 2), arg.countBytes() - 2)
            equal u64, equalError error = strings.findByte(body, 61)
            name := body
            value str
            hasValue bool = false
            if equalError.ok():
                name = strings.fromPtrNoCopy(strings.toPtr(body), equal)
                value = strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(body)) + equal + 1), body.countBytes() - equal - 1)
                hasValue = true
            ..
            def := try findLong(this, name)
            if def.kind != KIND_BOOL && hasValue == false:
                i = i + 1
                if i >= slices.count(arguments):
                    throw errors.invalidArgument("command-line option is missing its value")
                ..
                value = arguments[i]
                hasValue = true
            ..
            try apply(this, def, value, hasValue)
        elif options && arg.countBytes() > 1 && strings.byteAt(arg, 0) == 45:
            shortIndex u64 = 1
            loop shortIndex < arg.countBytes():
                def := try findShort(this, strings.byteAt(arg, shortIndex))
                value str
                hasValue bool = false
                if def.kind != KIND_BOOL:
                    if shortIndex + 1 < arg.countBytes():
                        value = strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(arg)) + shortIndex + 1), arg.countBytes() - shortIndex - 1)
                        hasValue = true
                        shortIndex = arg.countBytes()
                    else:
                        i = i + 1
                        if i >= slices.count(arguments):
                            throw errors.invalidArgument("command-line option is missing its value")
                        ..
                        value = arguments[i]
                        hasValue = true
                    ..
                ..
                try apply(this, def, value, hasValue)
                shortIndex = shortIndex + 1
            ..
        else:
            try appendBorrowed(addrof positional, this.allocator, arg)
        ..
        i = i + 1
    ..
    ret Result(allocator=this.allocator, values=move positional)
..

Result.positionals() str[]: ret this.values.view() ..
destr Result.free() void: this.values.free(this.allocator, none) ..

Parser.writeUsage(output writer.Writer) !void:
    try output.write("usage: ")
    try output.write(this.program)
    try output.write(" [options]\n")
    defs := this.definitions.view()
    for i u64 = 0 to this.definitions.count():
        try output.write("  --")
        try output.write(defs[i].name)
        if defs[i].short != 0:
            try output.write(", -")
            one := [1]u8
            one[0] = defs[i].short
            try output.write(strings.fromPtrNoCopy(slices.toPtr(one), 1))
        ..
        try output.write("  ")
        try output.writeLn(defs[i].help)
    ..
..

Parser.usage() !$str:
    text := try builder.new()
    defer text.free()

    try text.appendBorrowed("usage: ")
    try text.appendBorrowed(this.program)
    try text.appendBorrowed(" [options]\n")
    defs := this.definitions.view()
    for i u64 = 0 to this.definitions.count():
        try text.appendBorrowed("  --")
        try text.appendBorrowed(defs[i].name)
        if defs[i].short != 0:
            try text.appendBorrowed(", -")
            one := [1]u8
            one[0] = defs[i].short
            try text.appendCopy(strings.fromPtrNoCopy(slices.toPtr(one), 1))
        ..
        try text.appendBorrowed("  ")
        try text.appendBorrowed(defs[i].help)
        try text.appendBorrowed("\n")
    ..
    ret try text.build()
..

destr Parser.free() void:
    this.definitions.free(this.allocator, none)
..
