import std/[strutils, strformat, unicode]
import ./errors

type
  TokenKind* = enum
    tkIdent       ## bare identifier / keyword-looking word
    tkString      ## "quoted string" (may contain ${...} interpolation)
    tkNumber
    tkLBrace      ## {
    tkRBrace      ## }
    tkLBrack      ## [
    tkRBrack      ## ]
    tkLParen      ## (
    tkRParen      ## )
    tkEquals      ## =
    tkComma       ## ,
    tkDot         ## .
    tkColon       ## :
    tkQuestion    ## ?
    tkHeredocStart## <<EOT or <<-EOT marker; token stores the tag+indented flag
    tkOperator    ## + - * / % == != < > <= >= && || ! ...
    tkNewline
    tkComment
    tkEOF

  Token* = object
    kind*: TokenKind
    text*: string       ## raw text (decoded for strings)
    raw*: string         ## raw source slice (undecoded, quotes included)
    line*, col*: int
    heredocIndented*: bool  ## only for tkHeredocStart

  Lexer* = object
    src: string
    pos: int
    line: int
    col: int

proc newLexer*(src: string): Lexer =
  Lexer(src: src, pos: 0, line: 1, col: 1)

proc peekCh(lx: Lexer, offset: int = 0): char =
  let p = lx.pos + offset
  if p < 0 or p >= lx.src.len: '\0' else: lx.src[p]

proc atEnd(lx: Lexer): bool = lx.pos >= lx.src.len

proc advance(lx: var Lexer): char =
  result = lx.src[lx.pos]
  inc lx.pos
  if result == '\n':
    inc lx.line
    lx.col = 1
  else:
    inc lx.col

proc isIdentStart(c: char): bool =
  c.isAlphaAscii or c == '_' or c == '-'

proc isIdentCont(c: char): bool =
  c.isAlphaNumeric or c == '_' or c == '-'

proc skipInlineWs(lx: var Lexer) =
  ## Skip spaces/tabs/CR (not newlines - those are significant in HCL).
  while not lx.atEnd and lx.peekCh in {' ', '\t', '\r'}:
    discard lx.advance()

proc lexLineComment(lx: var Lexer): Token =
  let startLine = lx.line
  let startCol = lx.col
  var s = ""
  while not lx.atEnd and lx.peekCh != '\n':
    s.add lx.advance()
  Token(kind: tkComment, text: s, line: startLine, col: startCol)

proc lexBlockComment(lx: var Lexer): Token =
  let startLine = lx.line
  let startCol = lx.col
  discard lx.advance() # /
  discard lx.advance() # *
  var s = ""
  while not lx.atEnd:
    if lx.peekCh == '*' and lx.peekCh(1) == '/':
      discard lx.advance()
      discard lx.advance()
      return Token(kind: tkComment, text: s, line: startLine, col: startCol)
    s.add lx.advance()
  raise newHclLexError("unterminated block comment", startLine, startCol)

proc lexString(lx: var Lexer): Token =
  ## Lexes a double-quoted string. Interpolations `${...}` and escapes
  ## are decoded except for `${...}` which is preserved verbatim so
  ## HCL2 expressions inside strings are not lost.
  let startLine = lx.line
  let startCol = lx.col
  var raw = "\""
  discard lx.advance() # opening quote
  var decoded = ""
  while true:
    if lx.atEnd:
      raise newHclLexError("unterminated string literal", startLine, startCol)
    let c = lx.peekCh
    if c == '"':
      raw.add lx.advance()
      break
    elif c == '\\':
      raw.add lx.advance()
      if lx.atEnd:
        raise newHclLexError("unterminated escape sequence", startLine, startCol)
      let e = lx.advance()
      raw.add e
      case e
      of 'n': decoded.add '\n'
      of 't': decoded.add '\t'
      of 'r': decoded.add '\r'
      of '"': decoded.add '"'
      of '\\': decoded.add '\\'
      of '$': decoded.add '$'
      of 'u':
        # \uXXXX unicode escape
        var hex = ""
        for _ in 0..<4:
          if lx.atEnd: break
          let h = lx.advance()
          raw.add h
          hex.add h
        try:
          decoded.add Rune(parseHexInt(hex)).toUTF8
        except ValueError:
          decoded.add "\\u" & hex
      else:
        decoded.add '\\'
        decoded.add e
    elif c == '$' and lx.peekCh(1) == '{':
      # Preserve interpolation verbatim, tracking nested braces.
      raw.add lx.advance() # $
      raw.add lx.advance() # {
      decoded.add "${"
      var depth = 1
      while depth > 0:
        if lx.atEnd:
          raise newHclLexError("unterminated interpolation", startLine, startCol)
        let ic = lx.advance()
        raw.add ic
        decoded.add ic
        if ic == '{': inc depth
        elif ic == '}': dec depth
    elif c == '\n':
      raise newHclLexError("unterminated string literal (newline)", startLine, startCol)
    else:
      let ch = lx.advance()
      raw.add ch
      decoded.add ch
  raw.add "" # no-op, raw already includes closing quote
  Token(kind: tkString, text: decoded, raw: raw, line: startLine, col: startCol)

proc lexNumber(lx: var Lexer): Token =
  let startLine = lx.line
  let startCol = lx.col
  var s = ""
  while not lx.atEnd and (lx.peekCh.isDigit or lx.peekCh == '.'):
    # avoid consuming a trailing '.' that starts an identifier/attr access
    if lx.peekCh == '.' and not lx.peekCh(1).isDigit:
      break
    s.add lx.advance()
  if not lx.atEnd and lx.peekCh in {'e', 'E'}:
    var la = 1
    var exp = $lx.peekCh
    if lx.peekCh(1) in {'+', '-'}:
      exp.add lx.peekCh(1)
      la = 2
    if lx.peekCh(la).isDigit:
      s.add lx.advance()
      if lx.peekCh in {'+', '-'}:
        s.add lx.advance()
      while not lx.atEnd and lx.peekCh.isDigit:
        s.add lx.advance()
  Token(kind: tkNumber, text: s, line: startLine, col: startCol)

proc lexIdent(lx: var Lexer): Token =
  let startLine = lx.line
  let startCol = lx.col
  var s = ""
  while not lx.atEnd and lx.peekCh.isIdentCont:
    s.add lx.advance()
  Token(kind: tkIdent, text: s, line: startLine, col: startCol)

proc lexHeredoc(lx: var Lexer): Token =
  let startLine = lx.line
  let startCol = lx.col
  discard lx.advance() # <
  discard lx.advance() # <
  var indented = false
  if lx.peekCh == '-':
    indented = true
    discard lx.advance()
  var tag = ""
  while not lx.atEnd and lx.peekCh.isIdentCont:
    tag.add lx.advance()
  if tag.len == 0:
    raise newHclLexError("expected heredoc tag after <<", startLine, startCol)
  # consume rest of the line
  while not lx.atEnd and lx.peekCh != '\n':
    discard lx.advance()
  if not lx.atEnd: discard lx.advance() # consume newline
  var text = ""
  while true:
    if lx.atEnd:
      raise newHclLexError(&"unterminated heredoc <<{tag}", startLine, startCol)
    # capture the line
    let lineStart = lx.pos
    var lineBuf = ""
    while not lx.atEnd and lx.peekCh != '\n':
      lineBuf.add lx.advance()
    if not lx.atEnd: discard lx.advance() # consume '\n'
    let trimmed = strutils.strip(lineBuf, leading = true, trailing = false)
    if trimmed == tag or strutils.strip(lineBuf) == tag:
      break
    text.add lineBuf
    text.add "\n"
    discard lineStart
  if indented:
    # strip the common leading whitespace introduced by <<- form
    var minIndent = int.high
    for ln in text.splitLines():
      if strutils.strip(ln).len == 0: continue
      var n = 0
      for c in ln:
        if c == ' ' or c == '\t': inc n
        else: break
      if n < minIndent: minIndent = n
    if minIndent != int.high and minIndent > 0:
      var outLines: seq[string] = @[]
      for ln in text.splitLines():
        if ln.len >= minIndent: outLines.add ln[minIndent .. ^1]
        else: outLines.add strutils.strip(ln, leading = true, trailing = false)
      text = outLines.join("\n")
      if text.len > 0 and not text.endsWith("\n"): text.add "\n"
  Token(kind: tkHeredocStart, text: text, raw: tag, line: startLine, col: startCol,
        heredocIndented: indented)

const OperatorChars = {'+', '-', '*', '/', '%', '=', '!', '<', '>', '&', '|'}

proc lexOperator(lx: var Lexer): Token =
  let startLine = lx.line
  let startCol = lx.col
  let c1 = lx.advance()
  var s = $c1
  # two-char operators
  if not lx.atEnd:
    let c2 = lx.peekCh
    let two = s & c2
    if two in ["==", "!=", "<=", ">=", "&&", "||"]:
      s.add lx.advance()
  Token(kind: tkOperator, text: s, line: startLine, col: startCol)

proc next*(lx: var Lexer): Token =
  lx.skipInlineWs()
  if lx.atEnd:
    return Token(kind: tkEOF, line: lx.line, col: lx.col)
  let c = lx.peekCh
  let startLine = lx.line
  let startCol = lx.col
  case c
  of '\n':
    discard lx.advance()
    return Token(kind: tkNewline, line: startLine, col: startCol)
  of '#':
    return lx.lexLineComment()
  of '/':
    if lx.peekCh(1) == '/':
      return lx.lexLineComment()
    elif lx.peekCh(1) == '*':
      return lx.lexBlockComment()
    else:
      return lx.lexOperator()
  of '"':
    return lx.lexString()
  of '{': discard lx.advance(); return Token(kind: tkLBrace, text: "{", line: startLine, col: startCol)
  of '}': discard lx.advance(); return Token(kind: tkRBrace, text: "}", line: startLine, col: startCol)
  of '[': discard lx.advance(); return Token(kind: tkLBrack, text: "[", line: startLine, col: startCol)
  of ']': discard lx.advance(); return Token(kind: tkRBrack, text: "]", line: startLine, col: startCol)
  of '(': discard lx.advance(); return Token(kind: tkLParen, text: "(", line: startLine, col: startCol)
  of ')': discard lx.advance(); return Token(kind: tkRParen, text: ")", line: startLine, col: startCol)
  of ',': discard lx.advance(); return Token(kind: tkComma, text: ",", line: startLine, col: startCol)
  of ':': discard lx.advance(); return Token(kind: tkColon, text: ":", line: startLine, col: startCol)
  of '?': discard lx.advance(); return Token(kind: tkQuestion, text: "?", line: startLine, col: startCol)
  of '.':
    if lx.peekCh(1).isDigit:
      return lx.lexNumber()
    discard lx.advance()
    return Token(kind: tkDot, text: ".", line: startLine, col: startCol)
  of '=':
    if lx.peekCh(1) == '=':
      return lx.lexOperator()
    discard lx.advance()
    return Token(kind: tkEquals, text: "=", line: startLine, col: startCol)
  of '<':
    if lx.peekCh(1) == '<':
      return lx.lexHeredoc()
    return lx.lexOperator()
  else:
    if c.isDigit:
      return lx.lexNumber()
    elif c.isIdentStart:
      return lx.lexIdent()
    elif c in OperatorChars:
      return lx.lexOperator()
    elif c == '!':
      return lx.lexOperator()
    else:
      raise newHclLexError(&"unexpected character {escape($c)}", startLine, startCol)

proc tokenize*(src: string): seq[Token] =
  var lx = newLexer(src)
  result = @[]
  while true:
    let t = lx.next()
    result.add t
    if t.kind == tkEOF: break
