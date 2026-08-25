import hclnim
import std/strutils

const src = """
terraform {
  required_version = ">= 1.0"
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  count         = 2

  tags = {
    Name = "web-server"
    Env  = "prod"
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "instance ready"
    EOT
  }
}

output "region" {
  value = var.region
}
"""

let doc = parseHcl(src, hcl2)

echo "Terraform required_version: ",
  doc.blocks("terraform")[0]["required_version"].asString

for v in doc.blocks("variable"):
  echo "variable ", v.labels[0], " default=", v["default"].asString

for res in doc.blocks("resource"):
  echo "resource ", res.labels[0], ".", res.labels[1]
  echo "  instance_type = ", res["instance_type"].asString
  echo "  ami (expr)    = ", res["ami"].exprSrc
  for (k, v) in res["tags"].fields:
    echo "  tag ", k, " = ", v.asString
  for prov in res.blocks("provisioner"):
    echo "  provisioner ", prov.labels[0], " command:"
    echo "    ", prov["command"].heredocText.strip

for o in doc.blocks("output"):
  echo "output ", o.labels[0], " = ", o["value"].exprSrc
