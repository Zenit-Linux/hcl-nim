import std/unittest
import hclnim/lexer

suite "lexer":
  test "basic tokens":
    let toks = tokenize("a = 1")
    check toks[0].kind == tkIdent
    check toks[0].text == "a"
    check toks[1].kind == tkEquals
    check toks[2].kind == tkNumber
    check toks[2].text == "1"
    check toks[^1].kind == tkEOF

  test "strings with escapes":
    let toks = tokenize(""" "hello\nworld" """)
    check toks[0].kind == tkString
    check toks[0].text == "hello\nworld"

  test "string with interpolation preserved":
    let toks = tokenize(""" "hi ${name}" """)
    check toks[0].kind == tkString
    check toks[0].text == "hi ${name}"

  test "line comments":
    let toks = tokenize("# comment\na = 1")
    check toks[0].kind == tkComment
    check toks[1].kind == tkNewline
    check toks[2].kind == tkIdent

  test "slash-slash comments":
    let toks = tokenize("// comment\na = 1")
    check toks[0].kind == tkComment

  test "block comments":
    let toks = tokenize("/* multi\nline */a = 1")
    check toks[0].kind == tkComment
    check toks[1].kind == tkIdent

  test "numbers":
    check tokenize("42")[0].text == "42"
    check tokenize("3.14")[0].text == "3.14"
    check tokenize("1e10")[0].text == "1e10"
    # Note: a leading '-' is lexed as part of a bare identifier token
    # (dashes are legal inside HCL identifiers, e.g. `my-block`), so a
    # literal "-1" is not split into separate operator+number tokens by
    # the lexer alone. The *parser* still recovers the value correctly
    # as an expression - see test_parser.nim / test_hcl1.nim.

  test "braces and brackets":
    let toks = tokenize("{[()]}")
    check toks[0].kind == tkLBrace
    check toks[1].kind == tkLBrack
    check toks[2].kind == tkLParen
    check toks[3].kind == tkRParen
    check toks[4].kind == tkRBrack
    check toks[5].kind == tkRBrace

  test "operators":
    let toks = tokenize("a == b && c != d")
    check toks[1].kind == tkOperator
    check toks[1].text == "=="
    check toks[3].kind == tkOperator
    check toks[3].text == "&&"

  test "heredoc plain":
    let toks = tokenize("<<EOT\nhello\nworld\nEOT\n")
    check toks[0].kind == tkHeredocStart
    check toks[0].raw == "EOT"
    check toks[0].text == "hello\nworld\n"
    check toks[0].heredocIndented == false

  test "heredoc indented strips common indent":
    let toks = tokenize("<<-EOT\n  hello\n  world\n  EOT\n")
    check toks[0].kind == tkHeredocStart
    check toks[0].heredocIndented == true
    check toks[0].text == "hello\nworld\n"

  test "identifiers with dashes and underscores":
    let toks = tokenize("my-block_name")
    check toks[0].kind == tkIdent
    check toks[0].text == "my-block_name"

  test "dot token for attribute access":
    let toks = tokenize("a.b.c")
    check toks[0].kind == tkIdent
    check toks[1].kind == tkDot
    check toks[2].kind == tkIdent
