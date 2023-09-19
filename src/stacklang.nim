import stacklanglib
import prompt, unicode
import termstyle
import strutils except tokenize
import sequtils, tables, options, os
import nancy
import terminal

let isPipe = not isatty(stdin)
var shouldStyle = (not isPipe) and commandLineParams().len == 0

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

proc print(a: Element, command: string, pipe: File) =
  template printMessage(): untyped =
    var
      msg = ""
      first = true
    let wasStyling = shouldStyle
    shouldStyle = false
    while calc.stack.len > pos:
      let val = calc.stack.pop
      if val.kind == String:
        msg.insert(val.str.unescape(prefix="", suffix="") & (if first: "" else: " "))
      else:
        msg.insert($val & (if first: "" else: " "))
      first = false
    shouldStyle = wasStyling
    if shouldStyle: pipe.writeLine ""
    pipe.write msg
    if not shouldStyle: pipe.writeLine ""
  case a.kind:
  of Number:
    var pos = if a.num > 0'm:
      calc.stack.len - a.num.toInt
    else:
      abs(a.num.toInt)
    if pos >= 0 and calc.stack.len > pos:
      printMessage()
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
    printMessage()
  else: discard

defineCommands(ShellCommands, shellDocumentation, runShell):
  Input = "input"; "Reads a line from stdin and puts all tokens on the stack. Doesn't do anything on EOF, puts an empty string on an empty line":
    if shouldStyle: echo ""
    let line =
      try:
        var line = stdin.readLine
        if line.len == 0: "\"\"" else: line
      except EOFError: ""
    for token in line.tokenize:
      calc.stack.pushValue token
  Exhaust = "exhaust"; "Reads stdin until EOF putting everything on the stack":
    if not isPipe:
      raise newException(StackLangError, "Unable to run 'exhaust' when stdin is not a pipe")
    while true:
      try:
        for token in stdin.readLine().tokenize:
          calc.stack.pushValue token
      except EOFError: break
  Eof = (a, a, "eof"); "Checks if input is at the end of the file, runs the first label if it is, otherwise the second":
    if not isPipe:
      raise newException(StackLangError, "Unable to run 'eof' when stdin is not a pipe")
    if stdin.endOfFile:
      calc.evaluateElement(a)
    else:
      calc.evaluateElement(b)
  Exit = "exit"; "Exits interactive stacklang, saving custom commands":
    if shouldStyle: echo ""
    var output = open(getAppDir() / "custom.sl", fmWrite)
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
  Explain = (l|s, "explain"); "Prints out the documentation for a single command or category":
    if a.kind == Label and calc.isCommand a.lbl.Token:
      if shouldStyle: echo ""
      let padding = ' '.repeat(3)
      for category in calc.documentation.keys:
        for name, line in documentationLines(category):
          if name == a.lbl:
            stdout.write line.join padding
    elif (a.kind == Label and calc.documentation.hasKey a.lbl) or
         (a.kind == String and calc.documentation.hasKey a.str):
      if shouldStyle: echo ""
      for category in calc.documentation.keys:
        if category == (if a.kind == Label: a.lbl else: a.str):
          var help: TerminalTable
          for _, line in documentationLines(category):
            help.add line
          if help.rows > 0:
            help.echoTable(padding = 3)
    else:
      raiseInputError("No such command or category", (if a.kind == Label: a.lbl else: a.str))
  Display = (a, "display"); "Shows the element on top off the stack without poping it":
    if shouldStyle: echo ""
    stdout.write $a
    if not shouldStyle: echo ""
    calc.stack.push a
  Print = (n|l, "print"); "Takes a number of things or a label to go back to, then prints those things in FIFO order with space separators":
    print(a, command, stdout)
  ErrorPrint = (n|l, "eprint"); "Same as print, but prints to stderr instead of stdout":
    print(a, command, stderr)
  ListVariables = "list"; "Lists all currently stored variables":
    if calc.variables.len != 0:
      var variableTable: TerminalTable
      for key, value in calc.variables:
        variableTable.add $key, "[ " & value.mapIt($it).join(" ") & " ]"
      if shouldStyle: echo ""
      variableTable.echoTable(padding = 3)

calc.registerCommandRunner runShell, ShellCommands, "Interactive shell", shellDocumentation


calc.registerCommandRunner(proc (calc: Calc, argument: string): bool =
  if argument[0] == '!':
    result = true
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
  var backup: Calc
  if output:
    backup = new Calc
    backup.commandRunners = calc.commandRunners
    backup.stack = calc.stack
    backup.customCommands = calc.customCommands
    backup.documentation = calc.documentation
    backup.tmpCommands = calc.tmpCommands
    backup.variables = calc.variables
    backup.noEvalUntil = calc.noEvalUntil
    backup.commandEvalStack = calc.commandEvalStack
  template handle(): untyped =
    if not output: echo ""; quit 1
    calc = backup
    commandHistory.setLen commandHistory.len - 1
  try:
    for token in tokens:
      calc.evaluateToken(token)
    #calc.execute()
  except ArgumentError as e:
    echo red("\nError consuming element ") & $e.currentElement & red(" from command: ") & e.currentCommand
    stdout.write red e.msg
    handle()
  except InputError as e:
    echo red("\nError with input: "), e.input
    stdout.write red e.msg
    handle()
  except StackEmptyError as e:
    stdout.write red("\n" & e.msg)
    handle()
  except StackLangError as e:
    echo red("\nError with execution")
    stdout.write red e.msg
    handle()

  if output:
    if calc.stack.len != 0:
      echo ""
      stdout.write "[ " &  calc.stack.map(`$`).join("  ") & " ]"

if fileExists(getAppDir() / "custom.sl"):
  for input in lines(getAppDir() / "custom.sl"):
    evaluateString(input, false)
  reset commandHistory

proc dumpStack() =
  for e in 0..calc.stack.high:
    let element = calc.stack[e]
    stdout.write element
    if e != calc.stack.high: stdout.write " "
  stdout.write "\n"

proc handleCommandLine() =
  if commandLineParams().len > 0:
    if paramStr(1).startsWith "--":
      case paramStr(1):
      of "--help":
        echo "Stacklang v3.0.0"
        echo "Usage: stacklang [(--script <scriptfile>) | <command>]"
        echo "  --help                 Prints this help message"
        echo "  --version              Prints the version number line present above"
        echo "  --script <scriptfile>  Runs the script present in the file and quits"
        echo "  <command>              Runs a stacklang command"
        echo "If no arguments are present, starts an interactive session, to see"
        echo "language help run the 'help' command"
        quit 0
      of "--version":
        echo "Stacklang v3.0.0"
        quit 0
      of "--script":
        for input in lines(paramStr(2)):
          evaluateString(input, false)
        for input in commandLineParams()[2..^1]:
          evaluateString(input, false)
        if not isPipe:
          dumpStack()
          quit 0
    else:
      for input in commandLineParams():
        evaluateString(input, false)
      if not isPipe:
        dumpStack()
        quit 0

handleCommandLine()

var p: Prompt
if not isPipe:
  p = Prompt.init(promptIndicator = "> ", colorize = colorize)
  p.showPrompt()

while true:
  let input =
    try:
      if isPipe: stdin.readLine() else: p.readLine()
    except EOFError:
      dumpStack()
      quit 0
  evaluateString(input, shouldStyle)
  if shouldStyle:
    echo ""
