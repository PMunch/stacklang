import stacklanglib, tables, os, strutils, terminal
import rdstdin

var calc = Calc(stack: @[], customCommands: initTable[string, seq[string]](), tmpCommands: initTable[string, seq[string]](), variables: initTable[string, Stack[Element]]())
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
    except StackError as e:
      echo "Ran out of elements on stack while running \"", e.currentCommand, "\"!"
      #echo e.msg
      #echo e.getStackTrace()
      calc.stack = oldstack
      if not isatty(stdin):
        quit 1
      #raise getCurrentException()
    except:
      writeStackTrace()
      echo getCurrentExceptionMsg()
      calc.stack = oldstack
      if not isatty(stdin):
        quit 2
    humanEcho $calc.stack & " <- " & $commands
else:
  var output = ""
  if paramCount() == 1 and paramStr(1) == "--help":
    echo "Welcome to stacklang!"
    echo "When running stacklang from the terminal either supply each argument"
    echo "and escape them in your shell, or wrap them in a single quote"
    echo "statement. The calculations will be done, and of nothing is"
    echo "explicitly output the entire stack will be printed. Please use"
    echo "`display` or `print` to create output from your calculation. The"
    echo "commands in stacklang.custom are loaded when running in a shell but"
    echo "no new commands are added to it unless you run `exit`."
    echo ""
    output = calc.execute @["help"]
  elif paramCount() == 1:
    output = calc.execute paramStr(1).splitWhitespace()
  else:
    output = calc.execute commandLineParams()
  if output.len == 0:
    stdout.write calc.execute @["0", "print"]
  elif output != "\n":
    stdout.write output
