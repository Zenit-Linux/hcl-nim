import std/[os, json]
import ../hclnim

proc printUsage() =
  stderr.writeLine "usage: hcl2json [--hcl1|--hcl2] <file.hcl|->"
  stderr.writeLine ""
  stderr.writeLine "  --hcl1   parse input as legacy HCL v1 syntax"
  stderr.writeLine "  --hcl2   parse input as HCL v2 syntax (default)"
  stderr.writeLine "  -        read source from stdin"

proc main() =
  var version = hcl2
  var path = ""

  for arg in commandLineParams():
    case arg
    of "--hcl1": version = hcl1
    of "--hcl2": version = hcl2
    of "-h", "--help":
      printUsage()
      quit(0)
    else:
      path = arg

  if path.len == 0:
    printUsage()
    quit(1)

  let src =
    if path == "-":
      stdin.readAll()
    else:
      readFile(path)

  try:
    let doc = parseHcl(src, version)
    echo pretty(toJson(doc))
  except HclLexError, HclParseError:
    stderr.writeLine "hcl2json: parse error: " & getCurrentExceptionMsg()
    quit(1)

when isMainModule:
  main()
