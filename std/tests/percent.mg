mod main
use "std:errors" as errors
use "std:heap" as heap
use "std:percent" as percent
use "std:slices" as slices
use "std:strings" as strings

pub main() !void:
    a := heap.allocator()
    encoded := try percent.encode("a b/c", percent.URI_COMPONENT)
    defer encoded.free()
    if strings.compare(encoded, "a%20b%2Fc") == false:
        throw errors.failure("URI-component percent encoding changed")
    ..
    form := try percent.encode("a b+c", percent.FORM)
    defer form.free()
    if strings.compare(form, "a+b%2Bc") == false:
        throw errors.failure("form percent encoding changed")
    ..
    decoded := try percent.decodeForm(form)
    defer slices.free(decoded)
    if slices.count(decoded) != 5 || decoded[1] != 32 || decoded[3] != 43:
        throw errors.failure("form percent decoding changed")
    ..
    bad, badError := percent.decode("%G0")
    if badError.ok():
        slices.free(bad)
        throw errors.failure("invalid percent escape accepted")
    ..
..
