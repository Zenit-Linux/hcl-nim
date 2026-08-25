# hcl-nim

A [HCL](https://github.com/hashicorp/hcl) (HashiCorp Configuration
Language) parser for [Nim](https://nim-lang.org), supporting both
**HCL v1** (legacy Terraform ≤ 0.11 syntax) and **HCL v2** (current
`hashicorp/hcl` syntax).

```nim
import hclnim

let doc = parseHcl("""
resource "aws_instance" "web" {
  ami           = "ami-123456"
  instance_type = "t3.micro"
  count         = 2

  tags = {
    Name = "web-server"
  }
}
""")

for res in doc.blocks("resource"):
  echo res.labels           # @["aws_instance", "web"]
  echo res["ami"].asString  # "ami-123456"
  echo res["tags"]["Name"]  # error: use res["tags"].fields / see below
```

## Installation

```
nimble install hclnim
```

or add to your `.nimble` file:

```
requires "hclnim >= 0.1.0"
```

## Features

- Parses both HCL v1 and HCL v2 structural syntax:
  - Blocks and labeled blocks: `type "label1" "label2" { ... }`
  - Attributes: `name = value`
  - Strings, with `${...}` interpolation preserved verbatim
  - Numbers (int/float, exponents)
  - Booleans and `null`
  - Lists: `["a", "b", "c"]`
  - Inline objects: `{ key = value, ... }`
  - Heredocs: `<<EOT ... EOT` and indented `<<-EOT ... EOT`
  - Comments: `#`, `//`, and `/* ... */`
- HCL2-only expressions (variable/attribute references, function
  calls, arithmetic, conditionals, `for` expressions, etc.) are
  preserved as raw source text (`nkExpr` / `.exprSrc`) rather than
  evaluated - see [Design & limitations](#design--limitations).
- Conversion to `std/json`'s `JsonNode` via `toJson(doc)`.
- A minimal formatter (`$doc`) to render the AST back to HCL-ish text.
- Descriptive parse errors with line/column info (`HclParseError`,
  `HclLexError`).

## Usage

### Parsing

```nim
import hclnim

# from a string
let doc = parseHcl(hclSourceString)          # defaults to HCL v2
let doc1 = parseHcl(hclSourceString, hcl1)    # explicit HCL v1

# from a file
let doc = parseHclFile("main.tf")
```

### Walking the document

```nim
# Attributes at the top level / inside a block
let name = doc["name"].asString
if doc.hasAttr("optional_thing"):
  echo doc["optional_thing"].asString

# Blocks, optionally filtered by type
for res in doc.blocks("resource"):
  echo res.blockType    # "resource"
  echo res.labels       # @["aws_instance", "web"]
  for prov in res.blocks("provisioner"):
    echo prov.labels

# Lists
for item in doc["subnets"].items:
  echo item.asString

# Inline objects
for (key, value) in doc["tags"].fields:
  echo key, " = ", value.asString

# Heredocs
echo doc["script"].heredocText

# HCL2 expressions that reference variables, call functions, etc.
# are not evaluated - you get the raw source back:
echo doc["ami"].exprSrc   # e.g. "data.aws_ami.ubuntu.id"
```

### Converting to JSON

```nim
import hclnim
import std/json

let doc = parseHcl(src)
let j: JsonNode = toJson(doc)
echo pretty(j)
```

Blocks are grouped into JSON arrays by block type (mirroring how
`hashicorp/hcl`'s own JSON representation works); each block's
labels (if any) are exposed under an `__labels` key and its own
body under `__body`.

### Rendering back to text

```nim
echo $doc   # a best-effort HCL-like re-serialization (not byte-exact)
```

## AST overview

Every node is an `HclNode` (`ref object` with a `kind` discriminator
from `HclNodeKind`):

| Kind          | Meaning                                             |
|---------------|------------------------------------------------------|
| `nkDocument`  | root node, `.body: seq[HclNode]`                     |
| `nkBlock`     | `.blockType`, `.labels`, `.blockBody`                |
| `nkAttribute` | `.name`, `.value`                                    |
| `nkString`    | `.strVal` (decoded), `.raw` (source incl. quotes)    |
| `nkNumber`    | `.isInt`, `.intVal` / `.numVal`                      |
| `nkBool`      | `.boolVal`                                           |
| `nkNull`      | (no fields)                                          |
| `nkList`      | `.items: seq[HclNode]`                               |
| `nkObject`    | `.fields: seq[tuple[key: string, value: HclNode]]`   |
| `nkHeredoc`   | `.heredocTag`, `.heredocIndented`, `.heredocText`    |
| `nkExpr`      | `.exprSrc` - raw HCL2 expression source              |

Convenience procs: `blocks(node, blockType = "")`, `attributes(node)`,
`attr(node, name): Option[HclNode]`, `` `[]`(node, name) ``,
`hasAttr(node, name)`, `asString(node)`.

## Design & limitations

Full HCL2 semantics require evaluating an expression language against
a runtime context (variables, functions, `for` comprehensions,
conditionals, type conversions) that only makes sense in the context
of a specific consumer (e.g. Terraform). Rather than bundling a
partial, likely-incorrect expression evaluator, **hcl-nim parses
structure, not semantics**:

- Everything that is a literal (string, number, bool, null, list,
  object, heredoc) is parsed into a proper AST node you can use
  directly.
- Everything else HCL2 allows as an expression (references like
  `var.x`, function calls like `upper("x")`, arithmetic, ternaries,
  `for` expressions, splat expressions like `foo[*].id`, etc.) is
  captured verbatim as source text on an `nkExpr` node
  (`.exprSrc`), so no information is lost - you can re-parse or
  hand it to your own evaluator if you need one.

This keeps the library dependency-free, predictable, and equally
useful for HCL v1 and HCL v2 input, at the cost of not resolving
expressions itself. If your use case only needs structural access
(reading `resource` blocks, labels, plain attribute values, tags,
etc. - the majority of "read a `.tf`/`.hcl` file" use cases) this is
usually all you need.

## Development

```
nimble test      # run the full test suite
nim c -r smoke.nim  # ad-hoc smoke test with example Terraform-like input
```

## License

MIT - see [LICENSE](LICENSE).
