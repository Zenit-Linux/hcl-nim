version       = "0.1.0"
author        = "YOUR_NAME <YOUR_EMAIL@example.com>"
description   = "HCL (HashiCorp Configuration Language) v1 and v2 parser for Nim"
license       = "MIT"
srcDir        = "src"

# Deps

requires "nim >= 1.6.0"

# Tasks

task test, "Run the test suite":
  exec "nim c -r --hints:off --path:./src tests/test_lexer.nim"
  exec "nim c -r --hints:off --path:./src tests/test_parser.nim"
  exec "nim c -r --hints:off --path:./src tests/test_hcl1.nim"
  exec "nim c -r --hints:off --path:./src tests/test_hcl2.nim"
  exec "nim c -r --hints:off --path:./src tests/test_json.nim"
