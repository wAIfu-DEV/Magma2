mod main
use "std:env" as env
use "std:heap" as heap
use "std:strings" as strings
use "std:errors" as errors

pub main() !void:
    name := "MAGMA_STDLIB_ENV_TEST_7C3A"
    try env.unset(name)
    if env.has(name): throw errors.failure("unset variable reported present") ..
    try env.set(name, "hello")
    defer env.unset(name)
    value := try env.get(name)
    defer value.free()
    if strings.compare(value, "hello") == false:
        throw errors.failure("environment round trip changed")
    ..
    snapshot := try env.list()
    defer snapshot.free()
    entries := snapshot.view()
    found bool = false
    i u64 = 0
    loop i < entries.count():
        if strings.compare(entries[i], "MAGMA_STDLIB_ENV_TEST_7C3A=hello"):
            found = true
        ..
        i = i + 1
    ..
    if found == false: throw errors.failure("environment snapshot omitted test variable") ..
..
