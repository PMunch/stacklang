# Package

version       = "0.1.0"
author        = "PMunch"
description   = "An easy to use programmable RPN calculator"
license       = "MIT"
srcDir        = "src"
bin           = @["stacklang"]


# Dependencies

requires "nim >= 0.19.9"
requires "termstyle"
requires "https://github.com/PMunch/nim-prompt"
requires "npeg"
requires "macroutils"
requires "nancy"
