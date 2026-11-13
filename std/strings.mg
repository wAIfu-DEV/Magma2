mod strings
# String allocation, conversion, comparison, searching, splitting, and iteration.

use "std:allocator" as alc
use "std:memory"    as mem
use "std:cast"      as cast
use "std:errors"    as err
use "std:pair"      as pair
use "std:footgun"   as fg
use "std:checked"   as checked

const gl_nullTerm u8 = 0

# Returns the pointer to the underlying data of the string (u8 array).
# Allocating string APIs provide a null byte at s.countBytes(); borrowed views
# are not necessarily terminated at their logical end.
# @param s input string
# @complexity O(1)
# @returns borrowed pointer to the first byte
# @example
#   pointer := strings.toPtr(text)
pub toPtr(s str) u8*:
    ret s.__data
..

pub toPtrMove(s $str) $u8*:
    result u8* = s.__data
    fg.drop(move s)
    ret move result
..

# Allocates an owned, uninitialized string with size bytes plus a null terminator.
# @complexity O(1), excluding allocator cost
# @ownership Release with str.free(); the originating allocator is embedded.
# @example
#   text := try strings.alloc(32)
pub alloc(size u64) !$str:
    a := ctx.alloc
    if size == 0 - 1:
        throw err.wouldOverflow("string allocation size overflow")
    ..
    p u8* = try a.alloc(size + 1) # Zero terminated
    bounded p by size + 1, size < size + 1:
        p[size] = 0
    ..
    ret fromPtrMoveA(a, move p, size)
..

# Allocates an owned string and initializes every byte to fill.
# @complexity O(N)
# @ownership Release with str.free(); the originating allocator is embedded.
# @example
#   padding := try strings.allocFill(8, 32)
pub allocFill(size u64, fill u8) !$str:
    a := ctx.alloc
    if size == 0 - 1:
        throw err.wouldOverflow("string allocation size overflow")
    ..
    p u8* = try a.alloc(size + 1) # Zero terminated
    bounded p by size + 1, size < size + 1:
        for i u64 = 0 to size:
            p[i] = fill
        ..
        p[size] = 0
    ..
    ret fromPtrMoveA(a, move p, size)
..

pub realloc(prev $str, newSize u64) !$str:
    onerror prev.free()
    a := allocatorOf(prev)
    if a.isNull():
        throw err.invalidArgument("borrowed string cannot be reallocated")
    ..
    if newSize == 0 - 1:
        throw err.wouldOverflow("string allocation size overflow")
    ..
    prevPtr := toPtr(prev)
    p u8* = try a.realloc(prevPtr, newSize + 1) # Zero terminated
    bounded p by newSize + 1, newSize < newSize + 1:
        p[newSize] = 0
    ..
    fg.drop(move prev)
    ret fromPtrMoveA(a, move p, newSize)
..

# Returns a str from a pointer and a length in bytes.
# @warning This ties the lifetime of the input pointer to the output magma str,
# if the input pointer is deallocated or falls out of scope, it WILL result in
# invalid and unsafe reads from memory when using the output str, leading to
# SEGFAULTs in the best cases or security vulnerabilities in the worst.
# Prefer using fromPtr when unsure about lifetimes.
# @complexity O(1)
# @param p pointer to the first byte
# @param bytesCount number of bytes in the view
# @returns borrowed string view over p
# @example
#   view := strings.fromPtrNoCopy(pointer, byteCount)
pub fromPtrNoCopy(p ptr, bytesCount u64) str:
    unsafe:
        data u8* = p
        ret str(__data=data, __byteCount=bytesCount, __allocatorImpl=none, __allocatorVtable=none)
    ..
..

fromPtrMoveFields(impl ptr, vtable ptr, p $ptr, bytesCount u64) $str:
    unsafe:
        data u8* = p
        ret str(__data=data, __byteCount=bytesCount, __allocatorImpl=impl, __allocatorVtable=vtable)
    ..
..

fromPtrMoveA(a alc.Allocator, p $ptr, bytesCount u64) $str:
    ret fromPtrMoveFields(a.implementation(), a.dispatchTable(), move p, bytesCount)
..

allocatorPtr(value str*) ptr:
    ret addrof value.__allocatorImpl
..

allocatorOf(value str) alc.Allocator:
    ret alc.fromEmbedded(allocatorPtr(addrof value))
..

# Returns a str from a owned pointer and a length in bytes.
# @complexity O(1)
# @param p owned pointer to the first byte
# @param bytesCount number of bytes in the view
# @returns owned string p
# @example
#   view := strings.fromPtrMove(move pointer, byteCount)
pub fromPtrMove(p $ptr, bytesCount u64) $str:
    ret fromPtrMoveA(ctx.alloc, move p, bytesCount)
..

# Shrinks a string descriptor without changing its backing allocation.
# The string remains the same borrowed or owned value; only its logical length
# changes. Expanding through this API is rejected because capacity is unknown.
pub truncate(value str*, byteCount u64) bool:
    if byteCount > value.countBytes():
        ret false
    ..
    value.__byteCount = byteCount
    ret true
..

# Returns a str from a pointer and a length in bytes.
# This copies the contents of p into a newly allocated str
# @complexity O(N) depending on byte count
# @param a allocator used for the copy
# @param p pointer to the first byte
# @param byteCount number of bytes to copy
# @returns independently owned copy of byteCount bytes
# @example
#   text := try strings.fromPtr(pointer, byteCount)
pub fromPtr(p ptr, byteCount u64) !$str:
    a := ctx.alloc
    # SAFETY: checked sizes and ownership invariants bound the raw string operation.
    unsafe:
        if byteCount == 0:
            nt u8* = try a.alloc(1)
            *nt = 0
            ret fromPtrMoveA(a, move nt, 0)
        ..

        # cap size to 0 in case of impossibly large string size (9 exabytes in this case)
        # this should prevent classes of attacks using size overflow as vector
        max u64 = 0 - 1
        if byteCount > (max / 2):
            throw err.wouldOverflow("string too large")
        ..

        inData u8* = p
        strData u8* = try a.alloc(byteCount + 1) # Zero terminated

        for i u64 = 0 to byteCount:
            strData[i] = inData[i]
        ..

        strData[byteCount] = 0
        ret fromPtrMoveA(a, move strData, byteCount)
    ..
..

# Allocates an independent copy of a string.
# @complexity O(N)
# @ownership Release the returned string with the same allocator.
# @example
#   owned := try strings.copy(borrowed)
pub copy(s str) !$str:
    a := ctx.alloc
    byteCount u64 = s.countBytes()
    if byteCount == 0 - 1:
        throw err.wouldOverflow("string allocation size overflow")
    ..
    if byteCount == 0:
        nt u8* = try a.alloc(1)
        bounded nt by 1:
            nt[0] = 0
        ..
        ret fromPtrMoveA(a, move nt, 0)
    ..
    inData u8* = toPtr(s)
    strData u8* = try a.alloc(byteCount + 1) # Zero terminated
    bounded inData by byteCount, strData by byteCount + 1, byteCount < byteCount + 1:
        for i u64 = 0 to byteCount:
            strData[i] = inData[i]
        ..
        strData[byteCount] = 0
    ..
    ret fromPtrMoveA(a, move strData, byteCount)
..

# Returns an owned ASCII-lowercase copy of s. Bytes outside A-Z are unchanged.
# @complexity O(N)
# @ownership Release the returned string with the same allocator.
# @example
#   lower := try strings.toLower("Hello")
pub toLower(s str) !$str:
    a := ctx.alloc
    result $str = try copy(s)
    data u8* = toPtr(result)
    size := result.countBytes()
    bounded data by size:
        for i u64 = 0 to size:
            if data[i] >= 65 && data[i] <= 90:
                data[i] = data[i] + 32
            ..
        ..
    ..
    ret move result
..

# Returns an owned ASCII-uppercase copy of s. Bytes outside a-z are unchanged.
# @complexity O(N)
# @ownership Release the returned string with the same allocator.
# @example
#   upper := try strings.toUpper("Hello")
pub toUpper(s str) !$str:
    a := ctx.alloc
    result $str = try copy(s)
    data u8* = toPtr(result)
    size := result.countBytes()
    bounded data by size:
        for i u64 = 0 to size:
            if data[i] >= 97 && data[i] <= 122:
                data[i] = data[i] - 32
            ..
        ..
    ..
    ret move result
..

# Returns the byte at position idx in string, prefer utf8.Utf8Iter for UTF8-aware
# string traversal.
# @complexity O(1) regardless of size.
# @param s input string
# @param idx zero-based byte index
# @returns byte at idx
# @example
#   firstByte := strings.byteAt(text, 0)
pub byteAt(s str, idx u64) u8:
    unsafe:
        ret s.__data[idx]
    ..
..

# Copies the provided string into a null-terminated C string.
# @complexity O(N) depending on string size
# @param a allocator
# @param s string to copy
# @returns a null-terminated c-style string
# @example
#   cText := try strings.toCstr(text)
pub toCstr(s str) !$u8*:
    a := ctx.alloc
    size u64 = s.countBytes()
    if size == 0 - 1:
        throw err.wouldOverflow("C string allocation size overflow")
    ..
    if size == 0:
        nt u8* = try a.alloc(1)
        bounded nt by 1:
            nt[0] = 0
        ..
        ret nt
    ..
    p u8* = toPtr(s)
    np u8* = try a.alloc(size + 1)
    bounded p by size, np by size + 1, size < size + 1:
        for i u64 = 0 to size:
            np[i] = p[i]
        ..
        np[size] = 0
    ..
    ret np
..

# Returns the underlying string pointer without reading or copying its data.
# The caller must guarantee that the string has a null byte immediately after
# its logical data. Owned strings returned by allocating string APIs meet this
# precondition; arbitrary borrowed strings and substring views may not. This
# cannot be checked safely here because the byte after a borrowed view may not
# be readable memory.
# @complexity O(1)
# @param s string to copy
# @returns a null-terminated c-style string
# @example
#   cText := strings.toCstrNoCopy(ownedText)
pub toCstrNoCopy(s str) u8*:
    p u8* = toPtr(s)

    if p == none:
        ret addrof gl_nullTerm
    ..
    ret p
..

# Returns the length of a C-style string.
# Length is obtained through traversal of the string up to null-terminator,
# repeated use may cause performance degradation, especially with longer strings.
# @complexity O(N) depending on string size.
# @param cstr null-terminated C-style string
# @example
#   byteCount := strings.cStrLen(cText)
pub cStrLen(cstr u8*) u64:
    # SAFETY: checked sizes and ownership invariants bound the raw string operation.
    unsafe:
        len u64 = 0
        loop cstr[len] != 0:
            len = len + 1
        ..
        ret len
    ..
..

# Creates a magma-style str from a null-terminated C-string.
# This function does not copy the input C-string, instead it borrows it.
# @warning This ties the lifetime of the C-string to the output magma str,
# if the C-string is deallocated or falls out of scope, it WILL result in
# invalid and unsafe reads from memory when using the output str, leading to
# SEGFAULTs in the best cases or security vulnerabilities in the worst.
# Prefer using fromCstr when unsure about the input C-string lifetime.
# @complexity O(N) depending on string size. (due to length traversal)
# Prefer using fromPtr which is O(1) if you already know the length of the C-string.
# @param cstr null-terminated C-string
# @returns magma-style str
# @example
#   view := strings.fromCstrNoCopy(cText)
pub fromCstrNoCopy(cstr u8*) str:
    len u64 = cStrLen(cstr)
    ret fromPtrNoCopy(cstr, len)
..

# Creates a magma-style str from a null-terminated C-string.
# This function copies the C-string to the new str.
# @param cstr null-terminated C-string
# @returns magma-style str
# @complexity O(N)
# @ownership Release the returned string with str.free().
# @example
#   text := try strings.fromCstr(cText)
pub fromCstr(cstr u8*) !$str:
    a := ctx.alloc
    # SAFETY: checked sizes and ownership invariants bound the raw string operation.
    unsafe:
        size u64 = cStrLen(cstr)
        if size == 0 - 1:
            throw err.wouldOverflow("string allocation size overflow")
        ..
        if size == 0:
            nt u8* = try a.alloc(1)
            *nt = 0
            ret fromPtrMoveA(a, move nt, 0)
        ..
        strData u8* = try a.alloc(size + 1)

        for i u64 = 0 to size:
            strData[i] = cstr[i]
        ..
        strData[size] = 0
        ret fromPtrMoveA(a, move strData, size)
    ..
..

# Compares both strings and returns true if they are strictly equal in size and
# content on the byte level.
# @param a first string
# @param b second string
# @returns true if both strings are equal
# @complexity O(N)
# @example
#   same := strings.compare("magma", candidate)
pub compare(a str, b str) bool:
    ret a.compare(b)
..

# Returns the first byte index containing value.
# @complexity O(N). Returns outOfBounds when value is absent.
# @example
#   index := try strings.findByte(text, 10)
pub findByte(s str, value u8) !u64:
    size := s.countBytes()
    data := toPtr(s)
    bounded data by size:
        for index u64 = 0 to size:
            if data[index] == value:
                ret index
            ..
        ..
    ..
    throw err.outOfBounds("byte was not found in string")
..

matchesAt(source str, needle str, offset u64) bool:
    sourceSize := source.countBytes()
    needleSize := needle.countBytes()
    if offset > sourceSize || needleSize > sourceSize - offset:
        ret false
    ..
    sourceData := toPtr(source)
    needleData := toPtr(needle)
    bounded sourceData by sourceSize, needleData by needleSize:
        for index u64 = 0 to needleSize:
            bounded offset + index < sourceSize:
                if sourceData[offset + index] != needleData[index]:
                    ret false
                ..
            ..
        ..
    ..
    ret true
..

# Returns the first byte index at which needle occurs.
# @complexity O(N*M). An empty needle is found at index zero.
# @example
#   index := try strings.find(text, "needle")
pub find(s str, needle str) !u64:
    sourceSize := s.countBytes()
    needleSize := needle.countBytes()
    if needleSize == 0:
        ret 0
    ..
    if needleSize > sourceSize:
        throw err.outOfBounds("string was not found")
    ..
    limit := sourceSize - needleSize
    index u64 = 0
    loop index <= limit:
        if matchesAt(s, needle, index):
            ret index
        ..
        index = index + 1
    ..
    throw err.outOfBounds("string was not found")
..

# Allocates an independent substring spanning [start, end).
# @complexity O(end - start)
# @throws outOfBounds when the requested range is invalid
# @example
#   part := try strings.substring(text, 0, 5)
pub substring(s str, start u64, end u64) !$str:
    a := ctx.alloc
    size := s.countBytes()
    if start > end || end > size:
        throw err.outOfBounds("substring bounds are invalid")
    ..
    data := toPtr(s)
    ret try fromPtr(cast.utop(cast.ptou(data) + start), end - start)
..

# Returns a borrowed substring spanning [start, end).
# @complexity O1
# @throws outOfBounds when the requested range is invalid
# @example
#   part := try strings.view(text, 0, 5)
pub view(s str, start u64, end u64) !str:
    size := s.countBytes()
    if start > end || end > size:
        throw err.outOfBounds("substring bounds are invalid")
    ..
    data := toPtr(s)
    ret fromPtrNoCopy(cast.utop(cast.ptou(data) + start), end - start)
..

isTrimByte(value u8) bool:
    ret value == 32 || value == 9 || value == 10 || value == 11 || value == 12 || value == 13
..

# Allocates a copy without leading or trailing ASCII whitespace.
# @complexity O(N)
# @example
#   clean := try strings.trim("  magma  ")
pub trim(s str) !$str:
    a := ctx.alloc
    start u64 = 0
    size := s.countBytes()
    end := size
    data := toPtr(s)
    bounded data by size:
        loop start < end:
            bounded start < size:
                if isTrimByte(data[start]) == false:
                    break
                ..
            ..
            start = start + 1
        ..
        loop end > start:
            bounded end - 1 < size:
                if isTrimByte(data[end - 1]) == false:
                    break
                ..
            ..
            end = end - 1
        ..
    ..
    ret try substring(s, start, end)
..

# Allocates s without prefix when it starts with prefix, otherwise copies s.
# @complexity O(N)
# @example
#   value := try strings.trimPrefix(text, "prefix-")
pub trimPrefix(s str, prefix str) !$str:
    a := ctx.alloc
    prefixSize := prefix.countBytes()
    if matchesAt(s, prefix, 0):
        ret try substring(s, prefixSize, s.countBytes())
    ..
    ret try copy(s)
..

# Allocates s without suffix when it ends with suffix, otherwise copies s.
# @complexity O(N)
# @example
#   value := try strings.trimSuffix(text, ".mg")
pub trimSuffix(s str, suffix str) !$str:
    a := ctx.alloc
    sourceSize := s.countBytes()
    suffixSize := suffix.countBytes()
    if suffixSize <= sourceSize && matchesAt(s, suffix, sourceSize - suffixSize):
        ret try substring(s, 0, sourceSize - suffixSize)
    ..
    ret try copy(s)
..

# Owning eager split result. Both the pointer table and every item are owned.
pub Split(
    items str*
    size u64
    allocator alc.Allocator
)

# Returns the number of split parts.
# @complexity O(1)
Split.count() u64:
    ret this.size
..

# Returns a borrowed view of a split part.
# @complexity O(1)
# @throws outOfBounds when index is not a valid part index
# @example
#   first := try parts.get(0)
Split.get(index u64) !str:
    # SAFETY: checked sizes and ownership invariants bound the raw string operation.
    unsafe:
        if index >= this.size:
            throw err.outOfBounds("split index is out of bounds")
        ..
        ret this.items[index]
    ..
..

# Releases every owned part and the pointer table.
# @complexity O(N), where N is the number of parts
destr Split.free() void:
    # SAFETY: checked sizes and ownership invariants bound the raw string operation.
    unsafe:
        for index u64 = 0 to this.size:
            this.items[index].free()
        ..
        if this.items != none:
            this.allocator.free(this.items)
        ..
        this.items = none
        this.size = 0
    ..
..

countParts(s str, separator str) !u64:
    separatorSize := separator.countBytes()
    if separatorSize == 0:
        throw err.invalidArgument("split separator cannot be empty")
    ..
    sourceSize := s.countBytes()
    count u64 = 1
    position u64 = 0
    loop position + separatorSize <= sourceSize:
        if matchesAt(s, separator, position):
            count = count + 1
            position = position + separatorSize
        else:
            position = position + 1
        ..
    ..
    ret count
..

# Eagerly splits s and allocates every item independently.
# @complexity O(N + K), where K is the number of produced parts
# @ownership The returned Split owns its table and every part.
# @example
#   parts := try strings.split("a,b,c", ",")
pub split(s str, separator str) !$Split:
    a := ctx.alloc
    # SAFETY: checked sizes and ownership invariants bound the raw string operation.
    unsafe:
        partCount := try countParts(s, separator)
        maxU64 u64 = 0 - 1
        if partCount > maxU64 / sizeof str:
            throw err.wouldOverflow("split result is too large")
        ..
        items str* = try a.allocT[str](partCount)
        separatorSize := separator.countBytes()
        sourceSize := s.countBytes()
        partStart u64 = 0
        position u64 = 0
        made u64 = 0
        onerror:
            for cleanup u64 = 0 to made:
                items[cleanup].free()
            ..
            a.free(items)
        ..

        loop position + separatorSize <= sourceSize:
            if matchesAt(s, separator, position):
                item $str = try substring(s, partStart, position)
                items[made] = move item
                made = made + 1
                position = position + separatorSize
                partStart = position
            else:
                position = position + 1
            ..
        ..

        last $str = try substring(s, partStart, sourceSize)
        items[made] = move last
        ret Split(items=items, size=partCount, allocator=a)
    ..
..

# Owning lazy splitter. Source and separator are copied at construction, and
# each next call returns a new independently owned string.
pub SplitIterator(
    source str
    separator str
    position u64
    finished bool
    allocator alc.Allocator
)

# Creates a lazy owning splitter that produces one allocated item at a time.
# @complexity O(N) to initialize; each next call scans to the following separator
# @ownership Free the iterator and every string returned by next.
# @example
#   iterator := try strings.splitIter("a,b,c", ",")
pub splitIter(s str, separator str) !$SplitIterator:
    a := ctx.alloc
    if separator.countBytes() == 0:
        throw err.invalidArgument("split separator cannot be empty")
    ..
    sourceCopy := try copy(s)
    onerror sourceCopy.free()
    separatorCopy $str = try copy(separator)
    ret SplitIterator(source=move sourceCopy, separator=move separatorCopy, position=0, finished=false, allocator=a)
..

# Reports whether another part remains.
# @complexity O(1)
SplitIterator.hasData() bool:
    ret this.finished == false
..

# Allocates and returns the next split part.
# @complexity O(P), where P is the returned part length
# @throws outOfBounds when no part remains
# @ownership The caller owns the returned string.
SplitIterator.next() !$str:
    if this.finished:
        throw err.outOfBounds("split iterator is exhausted")
    ..
    sourceSize := this.source.countBytes()
    separatorSize := this.separator.countBytes()
    start := this.position
    position := start
    loop position + separatorSize <= sourceSize:
        if matchesAt(this.source, this.separator, position):
            this.position = position + separatorSize
            ret try substring(this.source, start, position)
        ..
        position = position + 1
    ..
    this.finished = true
    this.position = sourceSize
    ret try substring(this.source, start, sourceSize)
..

# Releases the iterator's copied source and separator strings.
# @complexity O(1), excluding allocator cost
destr SplitIterator.free() void:
    # SAFETY: checked sizes and ownership invariants bound the raw string operation.
    unsafe:
        this.source.free()
        this.separator.free()
    ..
..

# Splits at the first separator and allocates both halves independently.
# @complexity O(N)
# @ownership Both returned strings are independently owned.
# @example
#   pair := try strings.splitOnce("name=value", "=")
pub splitOnce(s str, separator str) !$pair.Pair[str, str]:
    a := ctx.alloc
    if separator.countBytes() == 0:
        throw err.invalidArgument("split separator cannot be empty")
    ..
    position := try find(s, separator)
    first := try substring(s, 0, position)
    onerror first.free()
    secondStart := position + separator.countBytes()
    second $str = try substring(s, secondStart, s.countBytes())
    result := pair.new[str, str](move first, move second)
    ret result
..

pub concat(a str, b str) !$str:
    allocator := ctx.alloc
    an := a.countBytes()
    bn := b.countBytes()

    regSize := try checked.uAdd(an, bn)
    allocationSize := try checked.uAdd(regSize, 1)
    region := try allocator.alloc(allocationSize)
    mem.copy(toPtr(a), region, an)
    
    region2 := cast.utop(cast.ptou(region) + an)
    mem.copy(toPtr(b), region2, bn)

    bounded region by allocationSize, regSize < allocationSize:
        region[regSize] = 0
    ..
    ret fromPtrMoveA(allocator, move region, regSize)
..

pub isEmpty(s str) bool:
    ret s.countBytes() == 0
..

pub isUninit(s str) bool:
    ret isEmpty(s) && toPtr(s) == none
..
