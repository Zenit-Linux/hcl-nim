import std/unittest
import hclnim

suite "HCL1-style documents":
  test "classic terraform 0.11 resource block":
    let src = """
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
    check doc.version == hcl1

    let vars = doc.blocks("variable")
    check vars.len == 1
    check vars[0].labels == @["name"]
    check vars[0]["default"].asString == "world"

    let res = doc.blocks("resource")[0]
    check res.labels == @["template_file", "greeting"]
    check res["template"].asString == "hello, ${var.name}"

    let varsBlock = res.blocks("vars")[0]
    check varsBlock["foo"].asString == "bar"

  test "provider block with nested map-like block":
    let src = """
      provider "aws" {
        region = "us-east-1"
      }

      resource "aws_security_group" "sg" {
        name = "allow_all"

        ingress {
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
        }
      }
    """
    let doc = parseHcl(src, hcl1)
    let sg = doc.blocks("resource")[0]
    let ingress = sg.blocks("ingress")[0]
    check ingress["from_port"].intVal == 0
    check ingress["protocol"].asString == "-1"

  test "count and interpolated references":
    let src = """
      resource "aws_instance" "web" {
        count = 3
        ami   = "${var.ami_id}"
        tags {
          Name = "web-${count.index}"
        }
      }
    """
    let doc = parseHcl(src, hcl1)
    let res = doc.blocks("resource")[0]
    check res["count"].intVal == 3
    check res["ami"].asString == "${var.ami_id}"
