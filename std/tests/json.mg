mod main

use "std:allocator" as allocator
use "std:builder" as builder
use "std:cast" as cast
use "std:context" as context
use "std:debug_alloc" as debug_alloc
use "std:errors" as errors
use "std:heap" as heap
use "std:json" as json
use "std:memory" as memory
use "std:slices" as slices
use "std:strings" as strings
use "std:writer" as writer

Capture impl writer.Writer(
    data u8*
    count u64
)

Capture.writeRaw(bytes str) !u64:
    count := bytes.countBytes()
    # SAFETY: render passes addrof its live Capture; its 1024-byte allocation
    # exceeds every test rendering and count tracks the initialized prefix.
    unsafe:
        destination := cast.utop(cast.ptou(this.data) + this.count)
        memory.copy(strings.toPtr(bytes), destination, count)
        this.count = this.count + count
    ..
    ret count
..

render(value json.Value, precision u64) !$str:
    temporary := ctx.alloc
    storage u8* = try temporary.allocT[u8](1024)
    defer temporary.free(storage)
    output Capture
    output.data = storage
    output.count = 0
    sink := output.protoBorrow[writer.Writer]()
    try value.writeWithPrecision(sink, precision)
    view := strings.fromPtrNoCopy(output.data, output.count)
    ret try strings.copy(view)
..

expectInvalid(input str) !void:
    value $json.Value, parseError error = json.parse(input)
    if parseError.ok():
        value.free()
        throw errors.failure("JSON parser accepted malformed input")
    ..
    if parseError.code() != errors.ERR_INVALID_ARG:
        throw errors.failure("JSON parser returned the wrong error category")
    ..
..

nestedJson(depth u64) !$str:
    output := try builder.new()
    defer output.free()
    for open u64 = 0 to depth:
        try output.appendBorrowed("[")
    ..
    try output.appendBorrowed("null")
    for close u64 = 0 to depth:
        try output.appendBorrowed("]")
    ..
    ret try output.build()
..

testParserCleanup() !void:
    options := debug_alloc.Options(initialCapacity=16, canGrow=true, rejectUntrackedFree=true)
    debug := try debug_alloc.new(heap.allocator(), options)
    defer debug.destroy()
    previous := ctx
    tracked := debug.allocator()
    ctx = context.Ctx(alloc=tracked, exec=previous.exec)
    defer:
        ctx = previous
    ..

    malformed $json.Value, malformedError error = json.parse("{\"outer\":[\"owned\",{\"inner\":true}],\"broken\":[1,]}")
    if malformedError.ok():
        malformed.free()
        throw errors.failure("malformed JSON unexpectedly parsed during cleanup test")
    ..
    if debug.stats().liveAllocations != 0:
        throw errors.failure("JSON parser leaked a partial parse")
    ..

    valid := try json.parse("{\"outer\":[\"owned\",{\"inner\":true}]}")
    valid.free()
    stats := debug.stats()
    if stats.liveAllocations != 0 || stats.rejectedFrees != 0:
        throw errors.failure("JSON parsed value cleanup is unbalanced")
    ..
..

pub main() !void:
    a allocator.Allocator = heap.allocator()

    nullValue := json.null()
    try nullValue.asNull()
    wrongBool bool, wrongType error = nullValue.asBool()
    if wrongType.code() != 6:
        throw errors.failure("JSON accessor accepted the wrong type")
    ..
    nullValue.free()

    truth := json.bool(true)
    if try truth.asBool() == false:
        throw errors.failure("JSON bool round trip failed")
    ..
    truth.free()
    integer := json.numberInt(-42)
    integerValue := try integer.asInt()
    integerFloat := try integer.asFloat()
    if integerValue != -42 || integerFloat != -42.0:
        throw errors.failure("JSON integer conversion failed")
    ..
    integer.free()
    floating := json.numberFloat(12.75)
    floatValue := try floating.asFloat()
    floatInteger := try floating.asInt()
    if floatValue != 12.75 || floatInteger != 12:
        throw errors.failure("JSON float conversion failed")
    ..
    floating.free()

    objectValue := try json.object()
    object := try objectValue.asObject()
    try object.set("answer", json.numberInt(41))
    try object.set("answer", json.numberInt(42))
    answer := try object.get("answer")
    answerValue := try answer.asInt()
    if answerValue != 42 || object.count() != 1:
        throw errors.failure("JSON object replacement failed")
    ..
    taken := try object.take("answer")
    takenValue := try taken.asInt()
    if takenValue != 42 || object.count() != 0:
        throw errors.failure("JSON object take failed")
    ..
    taken.free()
    try object.set("temporary", json.bool(false))
    try object.delete("temporary")
    if object.count() != 0:
        throw errors.failure("JSON object delete failed")
    ..

    arrayValue := try json.array()
    array := try arrayValue.asArray()
    specialBytes := [5]u8
    specialBytes[0] = 34
    specialBytes[1] = 92
    specialBytes[2] = 10
    specialBytes[3] = 9
    specialBytes[4] = 1
    special := strings.fromPtrNoCopy(slices.toPtr(specialBytes), 5)
    specialValue := try json.string(special)
    specialRoundTrip := try specialValue.asString()
    if specialRoundTrip.countBytes() != 5:
        throw errors.failure("JSON string payload round trip failed")
    ..
    try array.append(move specialValue)
    try array.append(json.numberInt(-7))
    second := try array.get(1)
    secondNumber := try second.asInt()
    if array.count() != 2 || secondNumber != -7:
        throw errors.failure("JSON array access failed")
    ..
    missing json.Value, boundsErr error = array.get(2)
    if boundsErr.code() != 2:
        throw errors.failure("JSON array accepted an out-of-bounds index")
    ..

    escaped := try render(arrayValue, 2)
    defer escaped.free()
    escapedLength := escaped.countBytes()
    if escapedLength != 21:
        throw errors.failure("JSON escaped output has the wrong length")
    ..
    expected := [21]u8
    expected[0] = 91
    expected[1] = 34
    expected[2] = 92
    expected[3] = 34
    expected[4] = 92
    expected[5] = 92
    expected[6] = 92
    expected[7] = 110
    expected[8] = 92
    expected[9] = 116
    expected[10] = 92
    expected[11] = 117
    expected[12] = 48
    expected[13] = 48
    expected[14] = 48
    expected[15] = 49
    expected[16] = 34
    expected[17] = 44
    expected[18] = 45
    expected[19] = 55
    expected[20] = 93
    byteIndex u64 = 0
    loop byteIndex < 21:
        if strings.byteAt(escaped, byteIndex) != expected[byteIndex]:
            throw errors.failure("JSON string escaping changed")
        ..
        byteIndex = byteIndex + 1
    ..

    nestedValue := try json.object()
    nested := try nestedValue.asObject()
    try nested.set("ok", json.bool(true))
    try object.set("items", move arrayValue)
    try object.set("nested", move nestedValue)
    encoded := try render(objectValue, 2)
    defer encoded.free()
    encodedLength := encoded.countBytes()
    if encodedLength < 2 || strings.byteAt(encoded, 0) != 123 || strings.byteAt(encoded, encodedLength - 1) != 125:
        throw errors.failure("JSON nested object serialization changed")
    ..
    objectValue.free()

    copied := try json.string("owned")
    ownedText := try copied.asString()
    if strings.compare(ownedText, "owned") == false:
        throw errors.failure("JSON owned string copy failed")
    ..
    cleanupValue := try json.array()
    cleanup := try cleanupValue.asArray()
    try cleanup.append(move copied)

    copiedBorrowed := try json.string("borrowed")
    if strings.compare(try copiedBorrowed.asString(), "borrowed") == false:
        cleanupValue.free()
        throw errors.failure("JSON borrowed string changed")
    ..
    try cleanup.append(move copiedBorrowed)
    transferredText := try strings.copy("transferred")
    transferredText.free()
    try cleanup.append(try json.string("transferred"))

    childValue := try json.array()
    child := try childValue.asArray()
    try child.append(json.bool(true))
    try cleanup.append(move childValue)
    cleanupValue.free()

    parsed := try json.parse(" {\"name\":\"Magma\",\"values\":[null,true,false,-12,1.25,6.02e2],\"unicode\":\"\\u00e9 \\ud83d\\ude25\"} \n")
    parsedObject := try parsed.asObject()
    if parsedObject.count() != 3:
        parsed.free()
        throw errors.failure("JSON object parsing changed")
    ..
    parsedName := try parsedObject.get("name")
    if strings.compare(try parsedName.asString(), "Magma") == false:
        parsed.free()
        throw errors.failure("JSON string parsing changed")
    ..
    parsedValues := try (try parsedObject.get("values")).asArray()
    if parsedValues.count() != 6 || try (try parsedValues.get(1)).asBool() == false:
        parsed.free()
        throw errors.failure("JSON array parsing changed")
    ..
    try (try parsedValues.get(0)).asNull()
    if try (try parsedValues.get(3)).asInt() != -12:
        parsed.free()
        throw errors.failure("JSON integer parsing changed")
    ..
    exponentValue := try (try parsedValues.get(5)).asFloat()
    if exponentValue < 601.999 || exponentValue > 602.001:
        parsed.free()
        throw errors.failure("JSON exponent parsing changed")
    ..
    unicodeValue := try parsedObject.get("unicode")
    if strings.compare(try unicodeValue.asString(), "é 😥") == false:
        parsed.free()
        throw errors.failure("JSON Unicode escape parsing changed")
    ..
    parsedEncoding := try render(parsed, 2)
    if strings.byteAt(parsedEncoding, 0) != 123 || strings.byteAt(parsedEncoding, parsedEncoding.countBytes() - 1) != 125:
        parsedEncoding.free()
        parsed.free()
        throw errors.failure("parsed JSON serialization changed")
    ..
    parsedEncoding.free()
    parsed.free()

    scalar := try json.parse("\"root\\nstring\"")
    if strings.compare(try scalar.asString(), "root\nstring") == false:
        scalar.free()
        throw errors.failure("JSON scalar root parsing changed")
    ..
    scalar.free()

    minimum := try json.parse("-9223372036854775808")
    if try minimum.asInt() != cast.utoi(9223372036854775808):
        minimum.free()
        throw errors.failure("JSON minimum integer parsing changed")
    ..
    minimum.free()

    maximum := try json.parse("9223372036854775807")
    if try maximum.asInt() != 9223372036854775807:
        maximum.free()
        throw errors.failure("JSON maximum integer parsing changed")
    ..
    maximum.free()

    aboveInteger := try json.parse("9223372036854775808")
    if try aboveInteger.asFloat() < 9223372036854770000.0:
        aboveInteger.free()
        throw errors.failure("JSON large number fallback changed")
    ..
    aboveInteger.free()

    smallExponent := try json.parse("1.25e-2")
    smallValue := try smallExponent.asFloat()
    if smallValue < 0.012499 || smallValue > 0.012501:
        smallExponent.free()
        throw errors.failure("JSON negative exponent parsing changed")
    ..
    smallExponent.free()

    allEscapes := try json.parse("\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0000\"")
    escapedText := try allEscapes.asString()
    if escapedText.countBytes() != 9 || strings.byteAt(escapedText, 0) != 34 || strings.byteAt(escapedText, 8) != 0:
        allEscapes.free()
        throw errors.failure("JSON escape decoding changed")
    ..
    allEscapes.free()

    duplicate := try json.parse("{\"key\":1,\"key\":2}")
    duplicateObject := try duplicate.asObject()
    if duplicateObject.count() != 1 || try (try duplicateObject.get("key")).asInt() != 2:
        duplicate.free()
        throw errors.failure("JSON duplicate-key semantics changed")
    ..
    duplicate.free()

    invalidInputs := [36]str
    invalidInputs[0] = ""
    invalidInputs[1] = " "
    invalidInputs[2] = "nul"
    invalidInputs[3] = "true false"
    invalidInputs[4] = ".5"
    invalidInputs[5] = "1."
    invalidInputs[6] = "01"
    invalidInputs[7] = "-"
    invalidInputs[8] = "1e"
    invalidInputs[9] = "1e+"
    invalidInputs[10] = "[1,]"
    invalidInputs[11] = "[,1]"
    invalidInputs[12] = "[1 2]"
    invalidInputs[13] = "["
    invalidInputs[14] = "{\"a\":1,}"
    invalidInputs[15] = "{\"a\" 1}"
    invalidInputs[16] = "{a:1}"
    invalidInputs[17] = "{"
    invalidInputs[18] = "\"unterminated"
    invalidInputs[19] = "\"bad\\xescape\""
    invalidInputs[20] = "\"\\u12\""
    invalidInputs[21] = "\"\\ud800\""
    invalidInputs[22] = "\"\\ud800\\u0041\""
    invalidInputs[23] = "\"\\udc00\""
    invalidInputs[24] = "[] trailing"
    invalidInputs[25] = "[truex]"
    invalidInputs[26] = "1e10000"
    invalidInputs[27] = "\"line
break\""
    invalidInputs[28] = "+1"
    invalidInputs[29] = "-01"
    invalidInputs[30] = "1..0"
    invalidInputs[31] = "1e+-2"
    invalidInputs[32] = "TRUE"
    invalidInputs[33] = "NaN"
    invalidInputs[34] = "Infinity"
    invalidInputs[35] = "1.7976931348623159e308"
    for invalidIndex u64 = 0 to 36:
        bounded invalidIndex < 36:
            try expectInvalid(invalidInputs[invalidIndex])
        ..
    ..

    invalidUtf8Bytes := [3]u8
    invalidUtf8Bytes[0] = 34
    invalidUtf8Bytes[1] = 255
    invalidUtf8Bytes[2] = 34
    invalidUtf8 := strings.fromPtrNoCopy(slices.toPtr(invalidUtf8Bytes), 3)
    try expectInvalid(invalidUtf8)

    deepest := try nestedJson(128)
    deepestValue := try json.parse(deepest)
    deepestValue.free()
    deepest.free()

    tooDeep := try nestedJson(129)
    try expectInvalid(tooDeep)
    tooDeep.free()

    try testParserCleanup()

    # Common value-only API: no public pointer values and one `try` can cover a
    # nested throwing call chain.
    document := try json.object()
    defer document.free()
    documentObject := try document.asObject()
    try documentObject.setString("name", "Magma")
    try documentObject.setInt("version", 2)
    if strings.compare(try document.get("name").asString(), "Magma") == false:
        throw errors.failure("JSON chained value lookup changed")
    ..

    items := try json.array()
    defer items.free()
    itemsArray := try items.asArray()
    try itemsArray.append(json.numberInt(10))
    try itemsArray.append(json.numberInt(20))
    if try itemsArray.get(1).asInt() != 20 || itemsArray.count() != 2:
        throw errors.failure("JSON direct array API changed")
    ..
..
