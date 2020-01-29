import stacklanglib, tables, os, strutils, terminal
import rdstdin

var calc = Calc(stack: @[], customCommands: initTable[string, seq[string]](), tmpCommands: initTable[string, seq[string]](), variables: initTable[string, Element]())
if fileExists(getAppDir() / "stacklang.custom"):
  for line in (getAppDir() / "stacklang.custom").lines:
    let words = line.splitWhitespace()
    calc.customCommands[words[^1]] = words[0..^2]

if paramCount() == 0:
  template humanEcho(args: varargs[string, `$`]) =
    if isatty(stdin):
      echo(join args)

  humanEcho "Welcome to stacklang!"
  humanEcho "This is a very simple stack based calculator/language. To see what"
  humanEcho "you can do with it type `help` or see the README"
  if fileExists(getAppDir() / "stacklang.custom"):
    humanEcho "Custom commands loaded from stacklang.custom, to see them use lscmd"
  else:
    humanEcho "No custom commands file found"
  humanEcho "Type `help` to see available commands"

  humanEcho calc.stack

  var input = ""

  while readLineFromStdin("> ", input):
    let commands = input.splitWhitespace()
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
else:
  if paramCount() == 1 and paramStr(1) == "--help":
    echo "Welcome to stacklang!"
    echo "When running stacklang from the terminal either supply each argument"
    echo "and escape them in your shell, or wrap them in a single quote"
    echo "statement. The calculations will be done, but by default nothing will"
    echo "be output. Please use `display` or `print` to create output from your"
    echo "calculation. The commands in stacklang.custom are loaded when running"
    echo "in a shell but no new commands are added to it unless you run `exit`."
    echo ""
    stdout.write calc.execute(@["help"])
  elif paramCount() == 1:
    stdout.write calc.execute paramStr(1).splitWhitespace()
  else:
    stdout.write calc.execute commandLineParams()
