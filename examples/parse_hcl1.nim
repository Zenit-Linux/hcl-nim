import hclnim

const src = """
variable "name" {
  default = "world"
}

resource "template_file" "greeting" {
  template = "hello, ${var.name}"

  vars {
    foo = "bar"
  }
}
"""

let doc = parseHcl(src, hcl1)
echo "parsed as: ", doc.version

let res = doc.blocks("resource")[0]
echo "resource ", res.labels
echo "template = ", res["template"].asString
echo "vars.foo = ", res.blocks("vars")[0]["foo"].asString
