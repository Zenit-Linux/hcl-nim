import hclnim
import std/json

const src = """
service "web" {
  port = 8080
  tags = ["prod", "public"]
  meta = {
    owner = "platform-team"
  }
}
"""

let doc = parseHcl(src)
echo pretty(toJson(doc))
