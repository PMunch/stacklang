# Package

version       = "3.0.0"
author        = "PMunch"
description   = "An easy to use programmable RPN calculator"
license       = "MIT"
srcDir        = "src"
bin           = @["stacklang"]
installExt    = @["nim"]


# Dependencies

requires "nim >= 2.0.0"
requires "termstyle"
requires "https://github.com/PMunch/nim-prompt >= 0.1.2"
requires "npeg"
requires "macroutils"
requires "nancy"
requires "mapm >= 0.3.3"
