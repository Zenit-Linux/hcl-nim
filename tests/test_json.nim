import std/unittest
import std/json
import hclnim

suite "toJson conversion":
  test "attributes become plain JSON fields":
    let doc = parseHcl("""
      name = "hello"
      count = 3
      enabled = true
    """)
    let j = toJson(doc)
    check j["name"].getStr == "hello"
    check j["count"].getInt == 3
    check j["enabled"].getBool == true

  test "blocks become arrays grouped by type":
    let doc = parseHcl("""
      variable "a" { default = 1 }
      variable "b" { default = 2 }
    """)
    let j = toJson(doc)
    check j["variable"].kind == JArray
    check j["variable"].len == 2
    check j["variable"][0]["__labels"][0].getStr == "a"
    check j["variable"][0]["__body"]["default"].getInt == 1

  test "nested objects and lists":
    let doc = parseHcl("""
      tags = { Name = "web", Env = "prod" }
      subnets = ["a", "b"]
    """)
    let j = toJson(doc)
    check j["tags"]["Name"].getStr == "web"
    check j["subnets"].len == 2
    check j["subnets"][1].getStr == "b"
