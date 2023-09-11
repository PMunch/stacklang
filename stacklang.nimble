# Package

version       = "0.1.0"
author        = "PMunch"
description   = "An easy to use programmable RPN calculator"
license       = "MIT"
srcDir        = "src"
bin           = @["stacklang"]
installExt    = @["nim"]


# Dependencies

requires "nim >= 0.19.9"
requires "termstyle"
requires "https://github.com/PMunch/nim-prompt >= 0.1.2"
requires "npeg"
requires "macroutils"
requires "nancy"
requires "mapm >= 0.3.3"
