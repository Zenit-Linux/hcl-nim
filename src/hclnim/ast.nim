import std/options

type
  HclVersion* = enum
    ## Which HCL dialect to parse. The concrete syntax accepted only
    ## differs in a few corner cases (see README), but the tag is kept
    ## on the root node so callers can tell what was requested.
    hcl1 = "HCLv1"
    hcl2 = "HCLv2"

  HclNodeKind* = enum
    nkDocument   ## root node: a list of top-level attributes/blocks
    nkBlock      ## a block: `type "label1" "label2" { ... }`
    nkAttribute  ## an attribute: `name = <value>`
    nkString     ## a quoted string literal (interpolations kept verbatim)
    nkNumber     ## a numeric literal
    nkBool       ## `true` / `false`
    nkNull       ## `null`
    nkList       ## `[ expr, expr, ... ]`
    nkObject     ## `{ key = expr, ... }` used as a *value* (not a block)
    nkHeredoc    ## `<<EOT ... EOT` / `<<-EOT ... EOT`
    nkExpr       ## any other HCL2 expression, stored as raw source text
                 ## (references, function calls, operators, for-expressions,
                 ## conditionals, etc.)

  HclNode* = ref HclNodeObj
  HclNodeObj* = object
    line*: int
    col*: int
    case kind*: HclNodeKind
    of nkDocument:
      version*: HclVersion
      body*: seq[HclNode]        ## nkAttribute | nkBlock
    of nkBlock:
      blockType*: string
      labels*: seq[string]
      blockBody*: seq[HclNode]   ## nkAttribute | nkBlock
    of nkAttribute:
      name*: string
      value*: HclNode
    of nkString:
      strVal*: string
      raw*: string               ## original source, including quotes
    of nkNumber:
      numVal*: float
      isInt*: bool
      intVal*: int64
    of nkBool:
      boolVal*: bool
    of nkNull:
      discard
    of nkList:
      items*: seq[HclNode]
    of nkObject:
      fields*: seq[tuple[key: string, value: HclNode]]
    of nkHeredoc:
      heredocTag*: string
      heredocIndented*: bool
      heredocText*: string
    of nkExpr:
      exprSrc*: string

proc newDocument*(version: HclVersion): HclNode =
  HclNode(kind: nkDocument, version: version, body: @[])

proc newBlock*(blockType: string, labels: seq[string] = @[]): HclNode =
  HclNode(kind: nkBlock, blockType: blockType, labels: labels, blockBody: @[])

proc newAttribute*(name: string, value: HclNode): HclNode =
  HclNode(kind: nkAttribute, name: name, value: value)

proc newStringNode*(s: string, raw: string = ""): HclNode =
  HclNode(kind: nkString, strVal: s, raw: (if raw.len > 0: raw else: s))

proc newIntNode*(i: int64): HclNode =
  HclNode(kind: nkNumber, isInt: true, intVal: i, numVal: i.float)

proc newFloatNode*(f: float): HclNode =
  HclNode(kind: nkNumber, isInt: false, numVal: f)

proc newBoolNode*(b: bool): HclNode =
  HclNode(kind: nkBool, boolVal: b)

proc newNullNode*(): HclNode =
  HclNode(kind: nkNull)

proc newListNode*(items: seq[HclNode] = @[]): HclNode =
  HclNode(kind: nkList, items: items)

proc newObjectNode*(): HclNode =
  HclNode(kind: nkObject, fields: @[])

proc newExprNode*(src: string): HclNode =
  HclNode(kind: nkExpr, exprSrc: src)

# --- convenience accessors -------------------------------------------------

proc blocks*(n: HclNode, blockType: string = ""): seq[HclNode] =
  ## Return direct child blocks, optionally filtered by `blockType`.
  let items =
    case n.kind
    of nkDocument: n.body
    of nkBlock: n.blockBody
    else: @[]
  result = @[]
  for item in items:
    if item.kind == nkBlock and (blockType.len == 0 or item.blockType == blockType):
      result.add item

proc attributes*(n: HclNode): seq[HclNode] =
  ## Return direct child attributes.
  let items =
    case n.kind
    of nkDocument: n.body
    of nkBlock: n.blockBody
    else: @[]
  result = @[]
  for item in items:
    if item.kind == nkAttribute:
      result.add item

proc attr*(n: HclNode, name: string): Option[HclNode] =
  ## Find the first attribute with the given name at this level and
  ## return its *value* node.
  for a in n.attributes:
    if a.name == name:
      return some(a.value)
  none(HclNode)

proc `[]`*(n: HclNode, name: string): HclNode =
  ## Shortcut for `attr(n, name)`. Raises KeyError if missing.
  let o = n.attr(name)
  if o.isNone:
    raise newException(KeyError, "no such attribute: " & name)
  o.get()

proc hasAttr*(n: HclNode, name: string): bool =
  n.attr(name).isSome

proc asString*(n: HclNode): string =
  ## Best-effort plain-text extraction of a scalar node's value.
  case n.kind
  of nkString: n.strVal
  of nkNumber: (if n.isInt: $n.intVal else: $n.numVal)
  of nkBool: $n.boolVal
  of nkNull: ""
  of nkHeredoc: n.heredocText
  of nkExpr: n.exprSrc
  else: ""
