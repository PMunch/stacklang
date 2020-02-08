import stacklanglib, tables, os, strutils, sequtils, terminal
from unicode import Rune, toRunes, `$`
import termstyle, prompt

var calc = Calc(stack: @[], customCommands: initTable[string, seq[string]](), tmpCommands: initTable[string, seq[string]](), variables: initTable[string, Stack[Element]]())
if fileExists(getAppDir() / "stacklang.custom"):
  for line in (getAppDir() / "stacklang.custom").lines:
    let words = line.splitWhitespace()
    calc.customCommands[words[^1]] = words[0..^2]

proc `$`(elem: Element): string =
  case elem.kind:
  of String:
    template colourise(val: string): string =
      if val in calc.customCommands:
        italic yellow val
      elif val in calc.tmpCommands:
        yellow val
      elif val in calc.variables:
        italic val
      elif (try: (discard parseEnum[Commands](val); true) except: false):
        bold val
      elif (try: (discard parseEnum[InternalCommands](val); true) except: false):
        bold italic val
      else:
        val
    if elem.strVal[0] == '\\':
      result &= "\\" & colourise(stacklanglib.`$`(elem)[1..^1])
    else:
      result &= colourise(stacklanglib.`$`(elem))
  of Float:
    result &= green stacklanglib.`$`(elem)

proc `$`(stack: Stack[Element]): string =
  result = blue "["
  for i, elem in stack:
    result &= $elem
    result &= (if i != stack.high: "  " else: "")
  result &= blue "]"

proc colorize(x: seq[Rune]): seq[Rune] {.gcsafe.} =
  for part in ($x).tokenize():
    if part.isSep == true:
      result &= toRunes(part.token)
    else:
      result &= toRunes(
        try:
          $Element(kind: Float, floatVal: parseFloat(part.token))
        except:
          $Element(kind: String, strVal: part.token)
      )

proc `$`(x: seq[seq[Message]]): string =
  if x.len == 0:
    ""
  else:
    # TODO: Rewrite to get better tab support
    join(
      x.mapIt(it.mapIt(
        case it.kind:
        of Text: it.strVal
        of MessageComponents.Tab: "\t"
        of Elem: $it.elem & " "
      ).join "")
      , "\n") & "\n"

if paramCount() == 0:
  template humanEcho(args: varargs[string, `$`]) =
    if isatty(stdin):
      echo(join args)

  humanEcho blue "Welcome to stacklang!"
  humanEcho "This is a very simple stack based calculator/language. To see what"
  humanEcho "you can do with it type `help` or see the README"
  if fileExists(getAppDir() / "stacklang.custom"):
    humanEcho "Custom commands loaded from stacklang.custom, to see them use lscmd"
  else:
    humanEcho "No custom commands file found"
  humanEcho "Type `help` to see available commands"

  humanEcho blue calc.stack

  var input = ""
  var prompt = Prompt.init(promptIndicator = "> ", colorize = colorize)
  prompt.showPrompt()

  while true:
    let input = prompt.readLine()
    echo ""
    let commands = input.splitWhitespace()
    let oldstack = calc.stack
    try:
      stdout.write calc.execute(commands)
    except StackError as e:
      echo red("Ran out of elements on stack while running \"", e.currentCommand, "\"!")
      #echo e.msg
      #echo e.getStackTrace()
      calc.stack = oldstack
      if not isatty(stdin):
        quit 1
      #raise getCurrentException()
    except:
      writeStackTrace()
      echo red getCurrentExceptionMsg()
      calc.stack = oldstack
      if not isatty(stdin):
        quit 2
    humanEcho $calc.stack# & blue " <- " & $commands
else:
  var output: seq[seq[Message]]
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
  else:
    stdout.write output
