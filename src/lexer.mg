mod lexer

use "std:utf8" utf
use "std:list" ls
use "std:memory" mem
use "std:cast" cast
use "std:strings" strgs
use "std:slices" slc
use "std:fmt" fmt
use "std:footgun" fg

use "shared/token_types" tkt
use "shared/filectx" fctx
use "shared/comperr" comperr
use "shared/origin" org

enum LxMode u8(
    DEFAULT=0
    STRING
    COMMENT
    NUMBER
    HEXNUM
)

Lexer(
    file fctx.FileCtx*,
    content str,
    escapedStringScratch $ls.List[u8]
    tokStart u64
    tokHasSpan bool
    tokHasSyntheticPrefix bool
    escapedStringScratchActive bool
    escapedStringScratchInitialized bool
    tokens $ls.List[tkt.Token]
    errors $ls.List[comperr.CompErr]
    pos org.FilePos
    currTok tkt.Token
    idx u64
    max u64
    mode LxMode
    isEscaped bool
)

destr Lexer.free() void:
    if this.escapedStringScratchInitialized:
        this.escapedStringScratch.free()
    ..
    this.tokens.free()
..

destr Lexer.finish() $ls.List[tkt.Token]:
    if this.escapedStringScratchInitialized:
        this.escapedStringScratch.free()
    ..
    ret move this.tokens
..

Lexer.hasTokenText() bool:
    ret this.tokHasSpan || this.tokHasSyntheticPrefix || (this.escapedStringScratchInitialized && this.escapedStringScratch.count() > 0)
..

Lexer.ensureScratch() !void:
    if not this.escapedStringScratchInitialized:
        scratch := try ls.new[u8](ctx.alloc, none)
        # SAFETY: escapedStringScratch starts zeroed and is assigned exactly once.
        unsafe:
            this.escapedStringScratch = move scratch
        ..
        this.escapedStringScratchInitialized = true
    ..
..

Lexer.startScratch() !void:
    if this.escapedStringScratchActive:
        ret
    ..
    try this.ensureScratch()
    this.escapedStringScratchActive = true
    if this.tokHasSpan:
        for i := this.tokStart to this.idx:
            try this.escapedStringScratch.pushRight(strgs.byteAt(this.content, i))
        ..
        this.tokHasSpan = false
    ..
..

Lexer.appendSourceBytes(width u64) !void:
    if this.escapedStringScratchInitialized && this.escapedStringScratchActive:
        for i := this.idx to this.idx + width:
            try this.escapedStringScratch.pushRight(strgs.byteAt(this.content, i))
        ..
    elif not this.tokHasSpan:
        this.tokStart = this.idx
        this.tokHasSpan = true
    ..
..

Lexer.appendEncoded(cpt utf.Codepoint) !void:
    encoded := array u8[4]
    written := try utf.encode(cpt.value, encoded)
    for i := 0 to written:
        try this.escapedStringScratch.pushRight(encoded[i])
    ..
..

Lexer.clearTokenText() !void:
    if this.escapedStringScratchActive:
        try this.escapedStringScratch.clearKeep()
    ..
    this.tokStart = 0
    this.tokHasSpan = false
    this.tokHasSyntheticPrefix = false
    this.escapedStringScratchActive = false
..

Lexer.toggleMode(mode LxMode) void:
	if this.mode == mode:
		this.mode = LxMode.DEFAULT
    else:
		this.mode = mode
    ..
..

consumeSize(l Lexer*, size u64) void:
    l.idx = l.idx + size
..

decodeFirst(l Lexer*) !utf.Codepoint:
    ret try decodeFrom(l, l.idx)
..

decodeFrom(l Lexer*, from u64) !utf.Codepoint:
    if from >= l.content.countBytes():
        throw "out of bounds"
    ..

    # create view of contents
    subs := strgs.toPtr(l.content)
    subs = cast.reinterpret[u8](cast.utop(cast.ptou(subs) + from))
    subSlc := slc.fromPtr(subs, l.content.countBytes() - from)

    ret try utf.decode(subSlc)
..

Lexer.peek() !utf.Codepoint:
    ret try decodeFirst(this)
..

Lexer.peekMany(out utf.Codepoint[], n u64) !void:
    if out.count() < n:
        throw "out of bounds"
    ..

    off u64 = 0
    for i := 0 to n:
        cpt := try decodeFrom(this, this.idx+off)
        off = off+cast.u8to64(cpt.width)
        out[i] = cpt
    ..
..

Lexer.flushReprBuff() !str:
    if this.escapedStringScratchActive:
        ret try strgs.fromPtr(slc.toPtr(this.escapedStringScratch.view()), this.escapedStringScratch.count())
    elif this.tokHasSyntheticPrefix:
        source := try strgs.view(this.content, this.tokStart, this.idx)
        ret try strgs.concat("u", source)
    elif this.tokHasSpan:
        ret try strgs.view(this.content, this.tokStart, this.idx)
    ..
    ret ""
..

Lexer.pushTokenAndClearBuff(tk tkt.Token) !void:
    try this.tokens.pushRight(tk)
    try this.clearTokenText()
    this.currTok = tkt.Token(
        repr="",
        type=tkt.TkType.NAME,
        pos=this.pos,
        kwType=tkt.KwType.NONE,
    )
	this.currTok.pos.column = this.currTok.pos.column + 1
..

Lexer.pushTokenBuff() !void:
    if not this.hasTokenText() && this.currTok.type != tkt.TkType.LIT_STR:
        ret
    ..

	this.currTok.repr = try this.flushReprBuff()

    if this.currTok.type == tkt.TkType.NONE || this.currTok.type == tkt.TkType.NAME:
        kwType, err := tkt.getKwFromRepr(this.currTok.repr)
        if err.ok():
            this.currTok.type = tkt.TkType.KEYWORD
            this.currTok.kwType = kwType
        ..
    ..

    this.tokens.pushRight(this.currTok)
    try this.clearTokenText()

    this.currTok = tkt.Token(
        repr="",
        type=tkt.TkType.NAME,
        pos=this.pos,
        kwType=tkt.KwType.NONE,
    )
	this.currTok.pos.column = this.currTok.pos.column + 1
..

global escapeTable := array utf.Codepoint['w'](
    `a`=utf.Codepoint(width=1, value=`a`),
    `b`=utf.Codepoint(width=1, value=`b`),
    `f`=utf.Codepoint(width=1, value=`f`),
    `n`=utf.Codepoint(width=1, value=`n`),
    `r`=utf.Codepoint(width=1, value=`r`),
    `t`=utf.Codepoint(width=1, value=`t`),
    `v`=utf.Codepoint(width=1, value=`v`),
    `\\`=utf.Codepoint(width=1, value=`\\`),
    `'`=utf.Codepoint(width=1, value=`'`),
    `"`=utf.Codepoint(width=1, value=`"`),
    '`'=utf.Codepoint(width=1, value=`\``),
)

characterEscape(cpt utf.Codepoint) utf.Codepoint:
    if cpt.width > 1 || cpt.value >= escapeTable.count():
        ret cpt
    ..
    idx := cast.u32to64(cpt.value)
    bounded idx < escapeTable.count():
        escaped := escapeTable[idx]
        if escaped.value == 0:
            ret cpt
        ..
        ret escaped
    ..
..

errorFatal(l Lexer*, code str, msg str, help str, pos org.FilePos) !void:
    l.errors.pushRight(comperr.CompErr(
        sev=comperr.Severity.ERROR, code=code, msg=msg, help=help,
        file=l.file, org=org.Origin(filePath=l.file.path, position=pos),
    ))
    throw msg
..

lexLitChar(l Lexer*, cpt utf.Codepoint) !void:
    delim := cpt
    start := l.pos
    
    consumeSize(l, cast.u8to64(cpt.width))

    if l.idx >= l.max: # FATAL
        try errorFatal(l, "UNTERM_CHARLIT", "unterminated character literal", "expected ' or ` after character literal", start)
    ..

    escaped := false
    if strgs.byteAt(l.content, l.idx) == '\\':
        escaped = true
        consumeSize(l, 1)
        if l.idx >= l.max: # FATAL
            try errorFatal(l, "UNTERM_CHARLIT_ESC", "unterminated character literal after escape character", "expected an escaped character followed by its closing delimiter", start)
        ..
    ..

    lit, e := l.peek()
    if e.nok() || (not escaped && lit.value == delim.value) || lit.value == '\n':
        try errorFatal(l, "INVALID_CHARLIT", "invalid character literal", "expected exactly one character", start)
    ..

    if escaped:
        lit = characterEscape(lit)
    ..

    if delim.value == `'` && lit.value > 0x7f:
        try errorFatal(l, "INVALID_WIDTH_CHARLIT", "non-ASCII character in 8-bit character literal", "use backticks for UTF-8 characters", start)
    ..
    
    consumeSize(l, cast.u8to64(lit.width))

    if l.idx >= l.max:
        try errorFatal(l, "UNTERM_CHARLIT", "unterminated character literal", "expected the matching closing delimiter", start)
    ..

    closing, closeErr := l.peek()
    if closeErr.nok() || closing.value != delim.value:
        try errorFatal(l, "INVALID_CHARLIT", "invalid character literal", "expected the matching closing delimiter", start)
    ..

    consumeSize(l, cast.u8to64(closing.width))

    kind := tkt.TkType.LIT_CHAR32
    if delim.value == `'`:
        kind = tkt.TkType.LIT_CHAR8
    ..

    w64 := cast.u8to64(lit.width)

    repr := try ctx.alloc.alloc(w64+1)
    reprSlc u8[] = slc.fromPtr(repr, w64+1)

    written := try utf.encode(lit.value, reprSlc)
    bounded w64 < reprSlc.count():
        reprSlc[w64] = 0
    ..

    if written != w64:
        throw "char lit repr size mismatch"
    ..

    l.tokens.pushRight(tkt.Token(kwType=tkt.KwType.NONE, type=kind, pos=start, repr=strgs.fromPtrMove(move repr, w64)))
    ret
..

isSpace(cpt utf.Codepoint) bool:
    ret cpt.value == ` ` || cpt.value == `\t` || cpt.value == `\n` || cpt.value == `\r`
..

handleNonAlphaKeyword(l Lexer*, cpt utf.Codepoint) !tkt.Token:
    bestMatch := ""
    bestSize u64 = 0
    bestKwType tkt.KwType = tkt.KwType._END

    i u64 = cast.u8to64(tkt.getKwFirstByteHead(strgs.byteAt(l.content, l.idx)))
    loop i != 0:
        kwT tkt.KwType = cast.u64to8(i)
        kw := try tkt.getKwRepr(kwT)
        kwLen := kw.countBytes()
        if kwLen > bestSize && kwLen <= l.max-l.idx:
            matches := true
            for byteIdx := 0 to kwLen:
                if strgs.byteAt(l.content, l.idx+byteIdx) != strgs.byteAt(kw, byteIdx):
                    matches = false
                    break
                ..
            ..

            if matches:
                bestMatch = kw
                bestSize = kwLen
                bestKwType = kwT
            ..
        ..
        i = cast.u8to64(tkt.getKwFirstByteNext(kwT))
    ..

    if bestMatch == "":
        targetedChar := try strgs.view(l.content, l.idx, l.idx+cast.u8to64(cpt.width))
        formated := fmt.str(ctx.alloc, "unexpected character '").str(targetedChar).str("' while expected keyword")
        fmtStr := try formated.toStr(ctx.alloc)
        defer fg.drop[str](move fmtStr)
        try errorFatal(l, "UNEXPECTED_CHAR", fmtStr, "", l.pos)
    ..

    ret tkt.Token(
        repr=bestMatch,
        pos=l.pos,
        type=tkt.TkType.KEYWORD,
        kwType=bestKwType,
    )
..

printErrors(l Lexer*) void:
    for i := 0 to l.errors.count():
        err, e := l.errors.get(i)
        if e.ok():
            err.log()
        ..
    ..
..

toggleCommentModeOff(l Lexer*, cpt utf.Codepoint) !void:
    l.mode = LxMode.DEFAULT

    try l.tokens.pushRight(tkt.Token(
        kwType=tkt.KwType.NEWLINE, type=tkt.TkType.KEYWORD,
        pos=l.pos, repr="\n"
    ))
    l.pos.line = l.pos.line + 1
    l.pos.column = 0

    consumeSize(l, cast.u8to64(cpt.width))
..

toggleStringMode(l Lexer*, cpt utf.Codepoint) !void:
    try l.pushTokenBuff()
    l.toggleMode(LxMode.STRING)

    if l.mode == LxMode.STRING:
        l.currTok.type = tkt.TkType.LIT_STR
    ..
    consumeSize(l, cast.u8to64(cpt.width))
..

escapeChar(c u32) u32:
    if c == `a`:
        ret `\a`
    elif c == `b`:
        ret `\b`
    elif c == `f`:
        ret `\f`
    elif c == `n`:
        ret `\n`
    elif c == `r`:
        ret `\r`
    elif c == `t`:
        ret `\t`
    elif c == `v`:
        ret `\v`
    elif c == `\\`:
        ret `\\`
    elif c == `'`:
        ret `'`
    elif c == `"`:
        ret `"`
    else:
        ret c
    ..
..

commitToken(l Lexer*, cpt utf.Codepoint) !void:
    try l.pushTokenBuff()

    if cpt.value == `\n`:
        try l.tokens.pushRight(tkt.Token(
            repr="\n",
            pos=l.pos,
            type=tkt.TkType.KEYWORD,
            kwType=tkt.KwType.NEWLINE,
        ))
        l.pos.line = l.pos.line+1
        l.pos.column = 0
    ..
    l.mode = LxMode.DEFAULT
    consumeSize(l, cast.u8to64(cpt.width))
..

toggleNumberMode(l Lexer*, cpt utf.Codepoint) !bool:
    prev := l.currTok.type
    l.currTok.type = tkt.TkType.LIT_NUM

    l.mode = LxMode.NUMBER

    if cpt.value == `-`:
        digits := array utf.Codepoint[2]
        err := l.peekMany(digits, 2)

        if err.nok() || not (digits[1].value >= `0` && digits[1].value <= `9`):
            l.currTok.type = prev
        else:
            ret true
        ..
    ..

    if cpt.value == `0`:
        digits := array utf.Codepoint[2]
        err := l.peekMany(digits, 2)

        if err.nok():
            ret true
        elif digits[1].value == `x` || digits[1].value == `X`:
            l.tokHasSyntheticPrefix = true
            l.mode = LxMode.HEXNUM
        else:
            ret true
        ..
    ..
    ret false
..

lexNonAlphaKw(l Lexer*, cpt utf.Codepoint) !void:
    try l.pushTokenBuff()
    l.mode = LxMode.DEFAULT

    tk := try handleNonAlphaKeyword(l, cpt)
    try l.pushTokenAndClearBuff(tk)
    consumeSize(l, tk.repr.countBytes())
..

lexHexNum(l Lexer*, cpt utf.Codepoint) !void:
    # In HEXNUM mode the buffer is "u0" only at the prefix marker.
    # Checking its size avoids converting and freeing the literal for every
    # hexadecimal digit.
    isPrefixMarker := (cpt.value == `x` || cpt.value == `X`) && l.tokHasSyntheticPrefix && l.tokHasSpan && l.idx-l.tokStart == 1
    isNumeric := cpt.value >= `0` && cpt.value <= `9`
    isHexAlpha := (cpt.value >= `a` && cpt.value <= `f`) || (cpt.value >= `A` && cpt.value <= `F`)

    if not (isPrefixMarker || isNumeric || isHexAlpha):
        try errorFatal(l, "UNEXPECTED_CHAR_HEX", "unexpected character in hex number literal", "valid characters in a hexadecimal literal are: [0-9a-fA-F]", l.pos)
    ..
..

pub run(f fctx.FileCtx*) !$ls.List[tkt.Token]:
    lctx := try initCtx(f)
    l := addrof lctx
    onerror lctx.free()

    defer printErrors(l)
    
    loop l.idx < l.max:
        cpt := try l.peek()

        l.pos.column = l.pos.column+1

        # reset comment mode after newline
        if cpt.value == `\n` && l.mode == LxMode.COMMENT:
				try toggleCommentModeOff(l, cpt)
			continue
		..

        # consume comment
        if l.mode == LxMode.COMMENT:
            consumeSize(l, cast.u8to64(cpt.width))
            continue
        ..

        # lex char literal
        if l.mode == LxMode.DEFAULT && (cpt.value == `\`` || cpt.value == `'`):
            try lexLitChar(l, cpt)
            continue
        ..

        isModeNonStr := l.mode == LxMode.DEFAULT || l.mode == LxMode.NUMBER || l.mode == LxMode.HEXNUM

        # toggle on comment
        # TODO: have a "can be commented" function instead of this bullshit
        if isModeNonStr && cpt.value == `#`:
			try l.pushTokenBuff()
			l.toggleMode(LxMode.COMMENT)
			consumeSize(l, cast.u8to64(cpt.width))
			continue
		..

        # toggle string mode
        if cpt.value == `"` && not l.isEscaped: # " <- TODO: fix the damn highlighting error
            try toggleStringMode(l, cpt)
            continue
        ..

        escapedInString := l.mode == LxMode.STRING && l.isEscaped
        if escapedInString && cpt.width == 1:
            cpt.value = escapeChar(cpt.value)
        ..

        if l.mode == LxMode.STRING && cpt.value == `\\` && not l.isEscaped:
            try l.startScratch()
            l.isEscaped = true
            consumeSize(l, cast.u8to64(cpt.width))
            continue
        ..

        l.isEscaped = false

        # commit token
        if isModeNonStr && isSpace(cpt):
            try commitToken(l, cpt)
            continue
        ..

        # TODO: bad pattern, fix this shit
        shouldWriteNum := false

        isNumeric := cpt.value >= `0` && cpt.value <= `9`

        # toggle on number mode
        if l.mode == LxMode.DEFAULT && (isNumeric || cpt.value == `-`) && not l.hasTokenText():
            shouldWriteNum = try toggleNumberMode(l, cpt)
        ..

        isNotAlphaNum := not ((cpt.value >= `a` && cpt.value <= `z`) || (cpt.value >= `A` && cpt.value <= `Z`) || isNumeric)
        isNotNumDot := not (l.mode == LxMode.NUMBER && cpt.value == `.`)

        if not shouldWriteNum && isModeNonStr && isNotAlphaNum && cpt.value != `_` && isNotNumDot:
            try lexNonAlphaKw(l, cpt)
            continue
        ..

        if l.mode == LxMode.NUMBER && not (isNumeric || cpt.value == `.` || cpt.value == `-`):
            try errorFatal(l, "UNEXPECTED_CHAR_NUM", "unexpected character in number literal", "valid characters in number literal are: [0-9.]", l.pos)
        ..

        if l.mode == LxMode.HEXNUM:
            try lexHexNum(l, cpt)
        ..

        if not l.hasTokenText():
            l.currTok.pos = l.pos
        ..

        if l.escapedStringScratchActive && escapedInString:
            try l.appendEncoded(cpt)
        else:
            try l.appendSourceBytes(cast.u8to64(cpt.width))
        ..
        consumeSize(l, cast.u8to64(cpt.width))
        continue
    ..

    if l.hasTokenText():
        try l.pushTokenBuff()
    ..
    ret lctx.finish()
..

initCtx(f fctx.FileCtx*) !$Lexer:
    ret Lexer(
        file=f,
        content=f.content,
        escapedStringScratch=mem.zeroValue[ls.List[u8]](),
        tokStart=0,
        tokHasSpan=false,
        tokHasSyntheticPrefix=false,
        escapedStringScratchActive=false,
        escapedStringScratchInitialized=false,
        tokens=try ls.new[tkt.Token](ctx.alloc, none),
        errors=try ls.new[comperr.CompErr](ctx.alloc, none),
        pos=org.FilePos(column=0, line=0),
        currTok=mem.zeroValue[tkt.Token](),
        idx=0,
        max=f.content.countBytes(),
        isEscaped=false,
        mode=LxMode.DEFAULT,
    )
..
