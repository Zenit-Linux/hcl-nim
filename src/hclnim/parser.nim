import std/[strutils, strformat]
import ./ast
import ./lexer
import ./errors

type
  Parser = object
    toks: seq[Token]
    pos: int
    version: HclVersion

proc newParser(src: string, version: HclVersion): Parser =
  Parser(toks: tokenize(src), pos: 0, version: version)

proc cur(p: Parser): Token = p.toks[p.pos]

proc peekKind(p: Parser, offset: int = 0): TokenKind =
  let i = p.pos + offset
  if i >= p.toks.len: tkEOF else: p.toks[i].kind

proc adv(p: var Parser): Token =
  result = p.toks[p.pos]
  if p.pos < p.toks.len - 1: inc p.pos

proc skipTrivia(p: var Parser, skipNewlines: bool = true) =
  ## Skip comments, and optionally newlines (newlines are significant
  ## as statement separators at block/document level, but not inside
  ## expressions).
  while true:
    case p.cur.kind
    of tkComment: discard p.adv()
    of tkNewline:
      if skipNewlines: discard p.adv()
      else: break
    else: break

proc skipTriviaAndCommas(p: var Parser) =
  while true:
    case p.cur.kind
    of tkComment, tkNewline, tkComma: discard p.adv()
    else: break

proc err(p: Parser, msg: string): ref HclParseError =
  newHclParseError(msg, p.cur.line, p.cur.col)

proc expect(p: var Parser, kind: TokenKind, what: string): Token =
  p.skipTrivia(skipNewlines = true)
  if p.cur.kind != kind:
    raise p.err(&"expected {what}, got '{p.cur.text}' ({p.cur.kind})")
  p.adv()

# forward decls
proc parseExpr(p: var Parser): HclNode
proc parseBody(p: var Parser, until: TokenKind): seq[HclNode]

proc collectRawExprText(p: var Parser, stopAt: set[TokenKind]): string =
  ## Fallback for HCL2 expressions this parser doesn't model structurally
  ## (arithmetic, conditionals, function calls, for-expressions, variable
  ## references, etc). Captures raw source tokens until a token in
  ## `stopAt` is seen at depth 0, preserving nesting of (), [], {}.
  var depth = 0
  var parts: seq[string] = @[]
  var prevKind = tkEOF
  while true:
    let k = p.cur.kind
    if depth == 0 and k in stopAt: break
    if k == tkEOF: break
    case k
    of tkLParen, tkLBrack, tkLBrace: inc depth
    of tkRParen, tkRBrack, tkRBrace:
      if depth == 0: break
      dec depth
    else: discard
    let t = p.adv()
    case t.kind
    of tkNewline, tkComment: discard # collapse newlines/comments in expressions
    else:
      let piece = (if t.kind == tkString: t.raw else: t.text)
      # avoid inserting a space where it would visually break member
      # access, calls, or grouping (a.b, f(x), a[0], f() )
      let noSpaceBefore = t.kind in {tkDot, tkComma, tkRParen, tkRBrack} or
                          (t.kind == tkLParen and prevKind in {tkIdent, tkRParen, tkRBrack})
      let noSpaceAfterPrev = prevKind in {tkDot, tkLParen, tkLBrack}
      if parts.len > 0 and not noSpaceBefore and not noSpaceAfterPrev:
        parts.add " "
      parts.add piece
      prevKind = t.kind
  parts.join("")

proc looksLikeSimpleValue(p: Parser): bool =
  ## Peek to decide whether what follows can be parsed as one of our
  ## structural literal kinds (string/number/bool/null/list/object/heredoc)
  ## as opposed to a general HCL2 expression that must be captured raw.
  case p.cur.kind
  of tkString, tkNumber, tkLBrack, tkLBrace, tkHeredocStart: true
  of tkIdent: p.cur.text in ["true", "false", "null"]
  else: false

proc parseListValue(p: var Parser): HclNode =
  discard p.expect(tkLBrack, "'['")
  result = newListNode()
  p.skipTrivia()
  while p.cur.kind != tkRBrack:
    if p.cur.kind == tkEOF:
      raise p.err("unterminated list, expected ']'")
    result.items.add parseExpr(p)
    p.skipTrivia()
    if p.cur.kind == tkComma:
      discard p.adv()
      p.skipTrivia()
    elif p.cur.kind != tkRBrack:
      # HCL allows newline-separated list items without commas
      continue
  discard p.expect(tkRBrack, "']'")

proc parseObjectValue(p: var Parser): HclNode =
  discard p.expect(tkLBrace, "'{'")
  result = newObjectNode()
  p.skipTriviaAndCommas()
  while p.cur.kind != tkRBrace:
    if p.cur.kind == tkEOF:
      raise p.err("unterminated object, expected '}'")
    var key: string
    if p.cur.kind == tkString:
      key = p.adv().text
    elif p.cur.kind == tkIdent:
      key = p.adv().text
    else:
      raise p.err(&"expected object key, got '{p.cur.text}'")
    p.skipTrivia(skipNewlines = false)
    if p.cur.kind == tkEquals:
      discard p.adv()
    elif p.cur.kind == tkColon:
      discard p.adv()
    else:
      raise p.err("expected '=' or ':' after object key")
    p.skipTrivia()
    let val = parseExpr(p)
    result.fields.add (key, val)
    p.skipTriviaAndCommas()
  discard p.expect(tkRBrace, "'}'")

proc parseExpr(p: var Parser): HclNode =
  p.skipTrivia(skipNewlines = false)
  let startLine = p.cur.line
  let startCol = p.cur.col
  var node: HclNode
  case p.cur.kind
  of tkString:
    let t = p.adv()
    node = newStringNode(t.text, t.raw)
  of tkNumber:
    let t = p.adv()
    if '.' in t.text or 'e' in t.text or 'E' in t.text:
      node = newFloatNode(parseFloat(t.text))
    else:
      try:
        node = newIntNode(parseBiggestInt(t.text))
      except ValueError:
        node = newFloatNode(parseFloat(t.text))
  of tkLBrack:
    node = parseListValue(p)
  of tkLBrace:
    node = parseObjectValue(p)
  of tkHeredocStart:
    let t = p.adv()
    node = HclNode(kind: nkHeredoc, heredocTag: t.raw,
                    heredocIndented: t.heredocIndented, heredocText: t.text)
  of tkIdent:
    if p.cur.text == "true":
      discard p.adv(); node = newBoolNode(true)
    elif p.cur.text == "false":
      discard p.adv(); node = newBoolNode(false)
    elif p.cur.text == "null":
      discard p.adv(); node = newNullNode()
    else:
      # identifier reference / function call / for-expr / etc -> raw expr
      let raw = collectRawExprText(p, {tkNewline, tkComma, tkRBrace, tkRBrack, tkEOF})
      node = newExprNode(raw)
  else:
    # operators (unary !, -), parens, or anything else: capture raw
    let raw = collectRawExprText(p, {tkNewline, tkComma, tkRBrace, tkRBrack, tkEOF})
    if raw.len == 0:
      raise p.err(&"unexpected token '{p.cur.text}' while parsing expression")
    node = newExprNode(raw)

  # HCL2 allows trailing operators to continue an expression on the same
  # logical line (e.g. `1 + 2`, `a ? b : c`, `foo.bar`). If we parsed a
  # structural literal but an operator/dot/question immediately follows,
  # degrade gracefully to a raw expression capturing the rest.
  p.skipTrivia(skipNewlines = false)
  if p.cur.kind in {tkOperator, tkDot, tkQuestion, tkLParen} and node.kind != nkExpr:
    var prefix =
      case node.kind
      of nkString: node.raw
      of nkNumber: (if node.isInt: $node.intVal else: $node.numVal)
      of nkBool: $node.boolVal
      of nkNull: "null"
      else: ""
    if prefix.len > 0:
      let rest = collectRawExprText(p, {tkNewline, tkComma, tkRBrace, tkRBrack, tkEOF})
      node = newExprNode(prefix & " " & rest)

  node.line = startLine
  node.col = startCol
  node

proc parseBlockOrAttr(p: var Parser): HclNode =
  p.skipTrivia()
  let startLine = p.cur.line
  let startCol = p.cur.col
  if p.cur.kind != tkIdent and p.cur.kind != tkString:
    raise p.err(&"expected identifier, got '{p.cur.text}' ({p.cur.kind})")
  let name = p.adv().text

  # collect zero or more quoted-string labels before '{' (real HCL block
  # labels are always quoted strings, e.g. `resource "aws_instance" "web" {`)
  var labels: seq[string] = @[]
  p.skipTrivia(skipNewlines = false)
  while p.cur.kind == tkString:
    labels.add p.adv().text
    p.skipTrivia(skipNewlines = false)

  if p.cur.kind == tkEquals:
    discard p.adv()
    p.skipTrivia(skipNewlines = false)
    let val = parseExpr(p)
    result = newAttribute(name, val)
    result.line = startLine
    result.col = startCol
  elif p.cur.kind == tkLBrace:
    discard p.adv()
    let body = parseBody(p, tkRBrace)
    discard p.expect(tkRBrace, "'}'")
    result = newBlock(name, labels)
    result.blockBody = body
    result.line = startLine
    result.col = startCol
  else:
    raise p.err(&"expected '=' or '{{' after '{name}', got '{p.cur.text}'")

proc parseBody(p: var Parser, until: TokenKind): seq[HclNode] =
  result = @[]
  while true:
    p.skipTrivia()
    if p.cur.kind == until or p.cur.kind == tkEOF:
      break
    result.add parseBlockOrAttr(p)
    p.skipTrivia(skipNewlines = false)
    # statements are separated by newlines (or are simply adjacent);
    # consume an optional trailing comment/newline before the next one
    if p.cur.kind == tkComment:
      discard p.adv()

proc parse*(src: string, version: HclVersion = hcl2): HclNode =
  ## Parse `src` as HCL source and return the document root node.
  ## Raises `HclParseError` / `HclLexError` on malformed input.
  var p = newParser(src, version)
  let body = parseBody(p, tkEOF)
  p.skipTrivia()
  if p.cur.kind != tkEOF:
    raise p.err(&"unexpected trailing token '{p.cur.text}'")
  result = newDocument(version)
  result.body = body
