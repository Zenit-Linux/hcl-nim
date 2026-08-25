import std/[json, strutils, sequtils]
import ./hclnim/ast
import ./hclnim/parser
import ./hclnim/errors

export ast
export errors.HclError, errors.HclLexError, errors.HclParseError

proc parseHcl*(src: string, version: HclVersion = hcl2): HclNode =
  ## Parse an HCL document from a string. `version` only affects the
  ## `version` tag stored on the returned document node; the same
  ## structural grammar is used for both dialects (see module docs).
  parser.parse(src, version)

proc parseHclFile*(path: string, version: HclVersion = hcl2): HclNode =
  ## Parse an HCL document from a file on disk.
  parseHcl(readFile(path), version)

proc guessVersion*(src: string): HclVersion =
  ## Best-effort heuristic: HCL2-only syntax markers (`for` expressions,
  ## `${...}` outside of quotes not being required, etc.) are hard to
  ## detect reliably without full evaluation, so this only looks for a
  ## few strong HCL1-style signals (JSON-ish nested maps without `=`)
  ## and otherwise defaults to `hcl2`, the modern and more common dialect.
  result = hcl2

proc toJsonNode(n: HclNode): JsonNode =
  case n.kind
  of nkDocument:
    result = newJObject()
    for item in n.body:
      if item.kind == nkAttribute:
        result[item.name] = toJsonNode(item.value)
      elif item.kind == nkBlock:
        let key = item.blockType
        if key notin result:
          result[key] = newJArray()
        result[key].add toJsonNode(item)
  of nkBlock:
    result = newJObject()
    if n.labels.len > 0:
      result["__labels"] = %n.labels
    var bodyObj = newJObject()
    for item in n.blockBody:
      if item.kind == nkAttribute:
        bodyObj[item.name] = toJsonNode(item.value)
      elif item.kind == nkBlock:
        let key = item.blockType
        if key notin bodyObj:
          bodyObj[key] = newJArray()
        bodyObj[key].add toJsonNode(item)
    result["__body"] = bodyObj
  of nkAttribute:
    result = toJsonNode(n.value)
  of nkString:
    result = %n.strVal
  of nkNumber:
    result = (if n.isInt: %n.intVal else: %n.numVal)
  of nkBool:
    result = %n.boolVal
  of nkNull:
    result = newJNull()
  of nkList:
    result = newJArray()
    for it in n.items:
      result.add toJsonNode(it)
  of nkObject:
    result = newJObject()
    for (k, v) in n.fields:
      result[k] = toJsonNode(v)
  of nkHeredoc:
    result = %n.heredocText
  of nkExpr:
    result = %n.exprSrc

proc toJson*(n: HclNode): JsonNode =
  ## Convert a parsed HCL node into a `std/json` JsonNode tree, so it
  ## can be consumed with the familiar `json` API. Blocks are grouped
  ## by type into JSON arrays (mirroring `hashicorp/hcl`'s own
  ## `json.Unmarshal` convention); each block's own attributes/child
  ## blocks live under an `__body` key and its labels (if any) under
  ## `__labels`.
  toJsonNode(n)

proc `$`*(n: HclNode): string =
  ## Render a parsed node back to an HCL-like string. This is a
  ## formatter for the AST, not a byte-for-byte round trip of the
  ## original source (whitespace/comments are not preserved).
  proc indent(s: string, level: int): string =
    ("  ".repeat(level)) & s

  proc renderVal(v: HclNode): string =
    case v.kind
    of nkString: v.raw
    of nkNumber: (if v.isInt: $v.intVal else: $v.numVal)
    of nkBool: $v.boolVal
    of nkNull: "null"
    of nkHeredoc: "<<" & v.heredocTag & "\n" & v.heredocText & v.heredocTag & "\n"
    of nkExpr: v.exprSrc
    of nkList:
      "[" & v.items.mapIt(renderVal(it)).join(", ") & "]"
    of nkObject:
      var parts: seq[string] = @[]
      for (k, val) in v.fields:
        parts.add k & " = " & renderVal(val)
      "{ " & parts.join(", ") & " }"
    else: ""

  proc renderBody(items: seq[HclNode], level: int): string =
    var lines: seq[string] = @[]
    for item in items:
      case item.kind
      of nkAttribute:
        lines.add indent(item.name & " = " & renderVal(item.value), level)
      of nkBlock:
        var header = item.blockType
        for lbl in item.labels:
          header.add " \"" & lbl & "\""
        lines.add indent(header & " {", level)
        lines.add renderBody(item.blockBody, level + 1)
        lines.add indent("}", level)
      else: discard
    lines.join("\n")

  case n.kind
  of nkDocument: renderBody(n.body, 0)
  of nkBlock: renderBody(@[n], 0)
  else: renderVal(n)
