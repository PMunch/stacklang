import stacklanglib, tables, os, strutils, terminal

template humanEcho(args: varargs[string, `$`]) =
  if isatty(stdin):
    echo(join args)

humanEcho "Welcome to stacklang!"
humanEcho "This is a very simple stack based calculator/language. To see what"
humanEcho "you can do with it type `help` or see the README"
var calc = Calc(stack: @[], customCommands: initTable[string, seq[string]](), tmpCommands: initTable[string, seq[string]](), variables: initTable[string, Element]())
if fileExists(getAppDir() / "stacklang.custom"):
  for line in (getAppDir() / "stacklang.custom").lines:
    let words = line.splitWhitespace()
    calc.customCommands[words[^1]] = words[0..^2]
  humanEcho "Custom commands loaded from stacklang.custom, to see them use lscmd"
else:
  humanEcho "No custom commands file found"
humanEcho "Type help to see available commands"

humanEcho calc.stack

while not stdin.endOfFile:
  let commands = stdin.readLine().splitWhitespace()
  let oldstack = calc.stack
  try:
    stdout.write calc.execute(commands)
  except IndexError:
    echo "Ran out of elements on stack!"
    calc.stack = oldstack
    if not isatty(stdin):
      quit 1
  except:
    writeStackTrace()
    echo getCurrentExceptionMsg()
    calc.stack = oldstack
    if not isatty(stdin):
      quit 2
  humanEcho $calc.stack & " <- " & $commands
