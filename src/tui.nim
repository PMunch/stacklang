import stacklang, tables, os, strutils, terminal

template humanEcho(args: varargs[string, `$`]) =
  if isatty(stdin):
    echo(join args)

humanEcho "Welcome to stacklang!"
humanEcho "This is a very simple stack based calculator/language that is a"
humanEcho "spiritual succesor to the greatness of the HP-41C. To add numbers or run"
humanEcho "commands simply type them here. You can also separate multiple numbers"
humanEcho "and commands by a space. You can also add text labels, and to add a"
humanEcho "label that has already been assigned to a custom command you can prefix"
humanEcho "it with a backslash. To see more of what you can do simply type 'help'"
var calc = Calc(stack: @[], customCommands: initTable[string, seq[string]](), tmpCommands: initTable[string, seq[string]](), variables: initTable[string, Element]())
if fileExists("stacklang.custom"):
  for line in "stacklang.custom".lines:
    let words = line.split(" ")
    calc.customCommands[words[^1]] = words[0..^2]
  humanEcho "Custom commands loaded from stacklang.custom, to see them use lscmd"
else:
  humanEcho "No custom commands file found"
humanEcho "Type help to see available commands"

humanEcho calc.stack

while not stdin.endOfFile:
  let commands = stdin.readLine().split(" ")
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
