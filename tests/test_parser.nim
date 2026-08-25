import std/unittest
import std/strutils
import hclnim

suite "parser - attributes and scalars":
  test "string attribute":
    let doc = parseHcl(""" name = "hello" """)
    check doc["name"].asString == "hello"

  test "int attribute":
    let doc = parseHcl("count = 3")
    check doc["count"].isInt
    check doc["count"].intVal == 3

  test "float attribute":
    let doc = parseHcl("ratio = 3.5")
    check doc["ratio"].isInt == false
    check doc["ratio"].numVal == 3.5

  test "bool attributes":
    let doc = parseHcl("a = true\nb = false")
    check doc["a"].boolVal == true
    check doc["b"].boolVal == false

  test "null attribute":
    let doc = parseHcl("a = null")
    check doc["a"].kind == nkNull

  test "list attribute":
    let doc = parseHcl("""items = ["a", "b", "c"]""")
    check doc["items"].kind == nkList
    check doc["items"].items.len == 3
    check doc["items"].items[1].asString == "b"

  test "list with trailing comma and newlines":
    let doc = parseHcl("""
      items = [
        "a",
        "b",
      ]
    """)
    check doc["items"].items.len == 2

  test "object attribute":
    let doc = parseHcl("""
      tags = {
        Name = "web"
        Env  = "prod"
      }
    """)
    check doc["tags"].kind == nkObject
    check doc["tags"].fields.len == 2
    check doc["tags"].fields[0].key == "Name"

  test "missing attribute raises KeyError":
    let doc = parseHcl("a = 1")
    expect(KeyError):
      discard doc["nope"]

  test "hasAttr":
    let doc = parseHcl("a = 1")
    check doc.hasAttr("a")
    check not doc.hasAttr("b")

suite "parser - blocks":
  test "simple block no labels":
    let doc = parseHcl("""
      settings {
        debug = true
      }
    """)
    let blocks = doc.blocks("settings")
    check blocks.len == 1
    check blocks[0].labels.len == 0
    check blocks[0]["debug"].boolVal == true

  test "block with two labels":
    let doc = parseHcl("""
      resource "aws_instance" "web" {
        ami = "ami-123"
      }
    """)
    let res = doc.blocks("resource")
    check res.len == 1
    check res[0].labels == @["aws_instance", "web"]
    check res[0]["ami"].asString == "ami-123"

  test "nested blocks":
    let doc = parseHcl("""
      outer {
        inner {
          value = 1
        }
      }
    """)
    let outer = doc.blocks("outer")[0]
    let inner = outer.blocks("inner")[0]
    check inner["value"].intVal == 1

  test "multiple blocks of same type":
    let doc = parseHcl("""
      variable "a" { default = 1 }
      variable "b" { default = 2 }
    """)
    let vars = doc.blocks("variable")
    check vars.len == 2
    check vars[0].labels == @["a"]
    check vars[1].labels == @["b"]

  test "attributes and blocks mixed":
    let doc = parseHcl("""
      name = "top"
      block1 {
        x = 1
      }
      other = 42
    """)
    check doc["name"].asString == "top"
    check doc["other"].intVal == 42
    check doc.blocks("block1").len == 1

suite "parser - comments":
  test "hash and slash comments ignored":
    let doc = parseHcl("""
      # a comment
      a = 1 // trailing
      /* block
         comment */
      b = 2
    """)
    check doc["a"].intVal == 1
    check doc["b"].intVal == 2

suite "parser - heredoc":
  test "heredoc value":
    let doc = parseHcl("""
      script = <<EOT
      echo hi
      EOT
    """)
    check doc["script"].kind == nkHeredoc
    check strutils.contains(doc["script"].heredocText, "echo hi")

suite "parser - HCL2 expressions preserved raw":
  test "variable reference":
    let doc = parseHcl("""value = var.name""")
    check doc["value"].kind == nkExpr
    check doc["value"].exprSrc == "var.name"

  test "function call":
    let doc = parseHcl("""value = upper("hi")""")
    check doc["value"].kind == nkExpr
    check doc["value"].exprSrc == "upper(\"hi\")"

  test "arithmetic expression":
    let doc = parseHcl("value = 1 + 2")
    check doc["value"].kind == nkExpr

suite "parser - errors":
  test "unterminated block raises HclParseError":
    expect(HclParseError):
      discard parseHcl("block {")

  test "unterminated string raises HclLexError":
    expect(HclLexError):
      discard parseHcl("a = \"unterminated")

  test "garbage after value raises":
    expect(HclParseError):
      discard parseHcl("a = 1 }")
