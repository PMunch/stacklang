import stacklanglib
import prompt, unicode
import termstyle
import strutils except tokenize
import sequtils, tables, options, os
import nancy
import terminal

let
  isPipe = not isatty(stdin)
  shouldStyle = (not isPipe) and commandLineParams().len == 0

proc intersperse(str: string, every: int, sep = '_'): string =
  var s = str
  if str[0] == '-':
    s = str[1..^1]
  result = s[0..min(s.high, s.high mod (every - 1))] & "_"
  for i in countup(s.high mod (every - 1) + 1, s.len - 1, every - 1):
    result &= s[i ..< i+(every-1)] & "_"
  result.setLen result.high
  if str[0] == '-':
    result.insert "-"

proc presentNumber(n: Element): string =
  try:
    case n.encoding:
    of Decimal:
      let x = n.num
      #case x.classify:
      #of fcNormal:
      #  let split = x.splitDecimal
      #  if split.floatpart.classify in [fcZero, fcNegZero]:
      #    ($split.intpart.int).intersperse(4)
      #  else:
      #    x.formatFloat(ffDecimal, precision = 32).strip(leading = false, chars = {'0'})
      #of fcSubnormal: x.formatFloat(ffScientific)
      #of fcZero: "0"
      #of fcNan: "nan"
      #of fcNegZero: "-0"
      #of fcInf: "inf"
      #of fcNegInf: "-inf"
      if abs(x) < 1000'm:
        $x
      else:
        x.formatMapm(separator = '_', decimals = if x.isInt: 0 else: -1)
    of Scientific:
      n.num.formatFloat(ffScientific, precision = -2)
    of Hexadecimal:
      var
        str = $n.num.toInt.toHex
        first = str[0]
      str = str.strip(trailing = false, chars = {first})
      str = str.align(((str.len + 1) div 2) * 2, first)
      str = str.intersperse(3)
      "0x" & str
    of Binary:
      var
        str = n.num.toInt.toBin(64)
        first = str[0]
      str = str.strip(trailing = false, chars = {first})
      str = str.align(((str.len + 8) div 8) * 8, first)
      str = str.intersperse(9)
      if str.len == 8 and n.num.toInt in 0..<16:
        "0b" & str[4..^1]
      else:
        "0b" & str[0..^1]
  except:
    $n.num

var
  calc = newCalc()
  commandHistory: seq[seq[Token]]

proc `$`(elem: Element): string =
  case elem.kind:
    of Label:
      if calc.isCommand(elem.lbl.Token):
        if calc.customCommands.hasKey(elem.lbl) or
          calc.tmpCommands.hasKey(elem.lbl):
          if shouldStyle: italic bold elem.lbl
          else: elem.lbl
        else:
          if shouldStyle: bold elem.lbl
          else: elem.lbl
      else:
        elem.lbl
    of Number:
      if shouldStyle: blue elem.presentNumber
      else: elem.presentNumber
    of String:
      if shouldStyle: yellow "\"" & elem.str & "\""
      else: "\"" & elem.str & "\""

proc `$`(command: seq[Token]): string =
  command.mapIt(it.string).join("  ")

calc.registerDefaults()

proc `$`(arguments: set[Argument]): string =
  arguments.toSeq.mapIt($it).join("|")

iterator documentationLines(category: string): tuple[name: string, line: seq[string]] =
  for cmd, doc in calc.documentation[category]:
    var arguments: string
    for i, argument in doc.arguments:
      arguments &=
        (if i == 0: "" else: "") &
        $argument &
        (if i == doc.arguments.high: "" else: ", ")
    if category == "Custom":
      yield (cmd, @[bold cmd, doc.msg, calc.customCommands[cmd].map(`$`).join("  ")])
    else:
      yield (cmd, @[bold cmd, arguments, doc.msg])

template raiseInputError(msg, argument: string): untyped =
  var e = newException(InputError, msg)
  e.input = argument
  raise e

proc toEvaluateable(el: Element): string =
  case el.kind:
  of Label: "\\" & el.lbl
  of String: "\"" & el.str & "\""
  of Number: el.presentNumber

defineCommands(ShellCommands, shellDocumentation, runShell):
  Exit = "exit"; "Exits interactive stacklang, saving custom commands":
    if shouldStyle: echo ""
    var output = open(getAppDir() / "stacklang.custom", fmWrite)
    for cmd, doc in calc.documentation["Custom"]:
      output.writeLine "\"", doc.msg, "\" ", cmd, " ", calc.customCommands[cmd].map(toEvaluateable).join(" "), " ", cmd, " mkcmd doccmd"
    output.close()
    quit 0
  History = "history"; "Prints out the entire command history so far":
    if shouldStyle: echo ""
    for i, command in commandHistory[0..^2]:
      stdout.write i, ": ", command, (if i != commandHistory.len - 2: "\n" else: "")
  Help = "help"; "Prints out all documentation":
    var customTable: TerminalTable
    if shouldStyle: echo ""
    for category in calc.documentation.keys:
      var help: TerminalTable
      for _, line in documentationLines(category):
        help.add line
      if category == "Custom":
        customTable = help
      elif help.rows > 0:
        echo category & " commands:"
        help.echoTable(padding = 3)
        echo ""
    if customTable.rows > 0:
      echo "Custom commands:"
      customTable.echoTable(padding = 3)
  Explain = (l, "explain"); "Prints out the documentation for a single command or category":
    if calc.isCommand a.Token:
      if shouldStyle: echo ""
      let padding = ' '.repeat(3)
      for category in calc.documentation.keys:
        for name, line in documentationLines(category):
          if name == a:
            stdout.write line.join padding
    elif calc.documentation.hasKey a:
      if shouldStyle: echo ""
      for category in calc.documentation.keys:
        if category == a:
          var help: TerminalTable
          for _, line in documentationLines(category):
            help.add line
          if help.rows > 0:
            help.echoTable(padding = 3)
    else:
      raiseInputError("No such command or category", a)
  Display = (a, "display"); "Shows the element on top off the stack without poping it":
    if shouldStyle: echo ""
    stdout.write $a
    if not shouldStyle: echo ""
    calc.stack.push a
  Print = (n|l, "print"); "Takes a number of things or a label to go back to, then prints those things in FIFO order with space separators":
    case a.kind:
    of Number:
      var pos = if a.num >= 0'm:
        calc.stack.len - a.num.toInt
      else:
        abs(a.num.toInt) - 1
      if pos >= 0 and calc.stack.len > pos:
        var msg = ""
        var first = true
        while calc.stack.len > pos:
          msg.insert(($calc.stack.pop) & (if first: "" else: " "))
          first = false
        if shouldStyle: echo ""
        stdout.write msg
        if not shouldStyle: echo ""
      else:
        var e = newException(ArgumentError, "Not enough element on stack to print")
        e.currentCommand = command
        e.currentElement = a
        raise e
    of Label:
      var pos = calc.stack.high
      while calc.stack[pos].kind != Label or calc.stack[pos].lbl != a.lbl:
        pos -= 1
      pos += 1
      var msg = ""
      while calc.stack.len > pos:
        msg.insert(($calc.stack.pop) & " ")
      if shouldStyle: echo ""
      stdout.write msg
      if not shouldStyle: echo ""
    else: discard
  ListVariables = "list"; "Lists all currently stored variables":
    if calc.variables.len != 0:
      var variableTable: TerminalTable
      for key, value in calc.variables:
        variableTable.add $key, "[ " & value.mapIt($it).join(" ") & " ]"
      if shouldStyle: echo ""
      variableTable.echoTable(padding = 3)

calc.registerCommandRunner runShell, ShellCommands, "Interactive shell", shellDocumentation


calc.registerCommandRunner(proc (calc: Calc, argument: string): bool =
  result = true
  if argument[0] == '!':
    try:
      var
        parts = argument[1..^1].split(':')
        pos = if parts[0] == "!": -1 else: parseInt(parts[0])
      if commandHistory.high == pos and parts.len == 1:
        raiseInputError("Can't expand current command", argument)
      if pos < 0:
        pos += commandHistory.high
      if commandHistory.high < pos or pos < 0:
        raiseInputError("Can't expand command, not enough commands", argument)
      case parts.len:
      of 1:
        commandHistory[^1] = @[]
        for token in commandHistory[pos]:
          calc.evaluateToken token
          commandHistory[^1].add token
      of 2:
        let subrange = parts[1].split('-')
        case subrange.len:
        of 1:
          let sub = parseInt(parts[1])
          if commandHistory[pos].high < sub:
            raiseInputError("Can't expand command, no such sub-command", argument)
          calc.evaluateToken commandHistory[pos][sub]
          commandHistory[^1] = @[commandHistory[pos][sub]]
        of 2:
          let
            start = parseInt(subrange[0])
            stop = if subrange[1].len > 0: parseInt(subrange[1]) else: commandHistory[pos].high
          if stop < start or commandHistory[pos].high < start or commandHistory[pos].high > stop:
            raiseInputError("Can't expand command, no such sub-command", argument)
          commandHistory[^1] = @[]
          for i in start..stop:
            calc.evaluateToken commandHistory[pos][i]
            commandHistory[^1].add commandHistory[pos][i]
        else:
          raiseInputError("Can't expand command, unable to parse segments", argument)
      else:
        raiseInputError("Can't expand command, too many segments", argument)
    except ValueError:
      raiseInputError("Can't expand command, unable to parse segments", argument)
  else:
    calc.stack.pushValue argument.Token
)

proc colorize(x: seq[Rune]): seq[Rune] = # {.gcsafe.} =
  for part in ($x).tokenize(withWhitespace = true):
    if part.string.isEmptyOrWhitespace == true:
      result &= toRunes(part.string)
    else:
      result &= toRunes(case part.toElement().kind:
        of Label:
          if calc.isCommand(part):
            if calc.customCommands.hasKey(part.string) or
              calc.tmpCommands.hasKey(part.string):
              italic bold part.string
            else:
              bold part.string
          else:
            part.string
        of Number: blue part.string
        of String: yellow part.string
      )

proc evaluateString(input: string, output = true) =
  let tokens = tokenize(input)
  commandHistory.add tokens
  # TODO: Replace this section once bug with copying is fixed
  let backup = new Calc
  backup.commandRunners = calc.commandRunners
  backup.stack = calc.stack
  #backup.awaitingCommands = calc.awaitingCommands
  backup.customCommands = calc.customCommands
  backup.documentation = calc.documentation
  backup.tmpCommands = calc.tmpCommands
  backup.variables = calc.variables
  backup.noEvalUntil = calc.noEvalUntil
  try:
    for token in tokens:
      calc.evaluateToken(token)
    #calc.execute()
  except ArgumentError as e:
    echo red("\nError consuming element ") & $e.currentElement & red(" from command: ") & e.currentCommand
    stdout.write red e.msg
    calc = backup
    commandHistory.setLen commandHistory.len - 1
  except InputError as e:
    echo red("\nError with input: "), e.input
    stdout.write red e.msg
    calc = backup
    commandHistory.setLen commandHistory.len - 1
  except StackEmptyError as e:
    stdout.write red("\n" & e.msg)
    calc = backup
    commandHistory.setLen commandHistory.len - 1
  except StackLangError as e:
    echo red("\nError with execution")
    stdout.write red e.msg
    calc = backup
    commandHistory.setLen commandHistory.len - 1

  if output:
    if calc.stack.len != 0:
      echo ""
      stdout.write "[ " &  calc.stack.map(`$`).join("  ") & " ]"

if fileExists(getAppDir() / "stacklang.custom"):
  for input in lines(getAppDir() / "stacklang.custom"):
    evaluateString(input, false)
  reset commandHistory

proc handleCommandLine() =
  if commandLineParams().len > 0:
    for input in commandLineParams():
      evaluateString(input, false)

proc dumpStack() =
  for e in 0..calc.stack.high:
    let element = calc.stack[e]
    stdout.write element
    if e != calc.stack.high: stdout.write " "
  stdout.write "\n"

if not isPipe:
  handleCommandLine()
  if commandLineParams().len > 0:
    dumpStack()
    quit 0

var p: Prompt
if not isPipe:
  p = Prompt.init(promptIndicator = "> ", colorize = colorize)
  p.showPrompt()

while true:
  let input =
    try:
      if isPipe: stdin.readLine() else: p.readLine()
    except EOFError:
      handleCommandLine()
      dumpStack()
      quit 0
  evaluateString(input, shouldStyle)
  if shouldStyle:
    echo ""
