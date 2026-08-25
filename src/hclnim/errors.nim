type
  HclError* = object of CatchableError

  HclLexError* = object of HclError
    line*: int
    col*: int

  HclParseError* = object of HclError
    line*: int
    col*: int

proc newHclLexError*(msg: string, line, col: int): ref HclLexError =
  result = newException(HclLexError, msg & " (line " & $line & ", col " & $col & ")")
  result.line = line
  result.col = col

proc newHclParseError*(msg: string, line, col: int): ref HclParseError =
  result = newException(HclParseError, msg & " (line " & $line & ", col " & $col & ")")
  result.line = line
  result.col = col
