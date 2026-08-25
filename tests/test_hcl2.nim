import std/unittest
import std/strutils
import hclnim

suite "HCL2-style documents":
  test "modern terraform resource with for_each and expressions":
    let src = """
      terraform {
        required_version = ">= 1.0"
      }

      variable "instance_count" {
        type    = number
        default = 2
      }

      resource "aws_instance" "web" {
        ami           = data.aws_ami.ubuntu.id
        instance_type = "t3.micro"
        count         = var.instance_count

        tags = {
          Name = "web-${count.index}"
        }
      }

      output "ids" {
        value = aws_instance.web[*].id
      }
    """
    let doc = parseHcl(src, hcl2)
    check doc.version == hcl2

    let tf = doc.blocks("terraform")[0]
    check tf["required_version"].asString == ">= 1.0"

    let v = doc.blocks("variable")[0]
    check v.labels == @["instance_count"]
    check v["default"].intVal == 2

    let res = doc.blocks("resource")[0]
    check res.labels == @["aws_instance", "web"]
    check res["ami"].kind == nkExpr
    check res["ami"].exprSrc == "data.aws_ami.ubuntu.id"
    check res["count"].kind == nkExpr
    check res["count"].exprSrc == "var.instance_count"

  test "heredoc with interpolation":
    let src = """
      locals {
        script = <<-EOT
          #!/bin/bash
          echo "hello ${var.name}"
        EOT
      }
    """
    let doc = parseHcl(src, hcl2)
    let locals = doc.blocks("locals")[0]
    check locals["script"].kind == nkHeredoc
    check strutils.contains(locals["script"].heredocText, "hello ${var.name}")

  test "function calls and nested lists":
    let src = """
      locals {
        names = concat(["a", "b"], ["c"])
        upper_name = upper("hello")
      }
    """
    let doc = parseHcl(src, hcl2)
    let locals = doc.blocks("locals")[0]
    check locals["names"].kind == nkExpr
    check locals["upper_name"].exprSrc == "upper(\"hello\")"

  test "module block":
    let src = """
      module "vpc" {
        source  = "terraform-aws-modules/vpc/aws"
        version = "5.0.0"
        cidr    = "10.0.0.0/16"
      }
    """
    let doc = parseHcl(src, hcl2)
    let m = doc.blocks("module")[0]
    check m.labels == @["vpc"]
    check m["source"].asString == "terraform-aws-modules/vpc/aws"
    check m["cidr"].asString == "10.0.0.0/16"

  test "boolean and null literals":
    let src = """
      settings {
        enabled = true
        optional = null
        disabled = false
      }
    """
    let doc = parseHcl(src, hcl2)
    let s = doc.blocks("settings")[0]
    check s["enabled"].boolVal == true
    check s["disabled"].boolVal == false
    check s["optional"].kind == nkNull
