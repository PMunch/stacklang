import stacklanglib
import prompt, unicode, termstyle
import strutils except tokenize
import sequtils, math, tables, options
import nancy

proc presentNumber(n: Element): string =
  case n.encoding:
  of Decimal:
    let x = n.num
    case x.classify:
    of fcNormal:
      let split = x.splitDecimal
      if split.floatpart.classify in [fcZero, fcNegZero]:
        $split.intpart.int
      else:
        x.formatFloat(ffDecimal, precision = 32).strip(leading = false, chars = {'0'})
    of fcSubnormal: x.formatFloat(ffScientific)
    of fcZero: "0"
    of fcNan: "nan"
    of fcNegZero: "-0"
    of fcInf: "inf"
    of fcNegInf: "-inf"
  of Hexadecimal:
    "0x" & n.num.int.toHex.strip(trailing = false, chars = {'0'})
  of Binary:
    #"0b" & n.num.int.toBin(64).strip(trailing = false, chars = {'0'})
    # All binary numbers are presented in groups of 8 with _ separators
    var
      str = n.num.int.toBin(64)
      first = str[0]
    if first == '0':
      str = str.strip(trailing = false, chars = {'0'})
    else:
      str = str.strip(trailing = false, chars = {'1'})
    str = str.align(((str.len + 8) div 8) * 8, first)
    var retstr = ""
    for i in countup(0, str.len - 1, 8):
      retstr &= str[i .. i+7] & "_"
    if retstr.len == 9 and n.num.int in 0..<16:
      "0b" & retstr[4..^2]
    else:
      "0b" & retstr[0..^2]

var
  calc = newCalc()
  commandHistory: seq[seq[Token]]

proc `$`(elem: Element): string =
  case elem.kind:
    of Label:
      if calc.isCommand(elem.lbl.Token):
        if calc.customCommands.hasKey(elem.lbl):
          italic bold elem.lbl
        else:
          bold elem.lbl
      else:
        elem.lbl
    of Number: blue elem.presentNumber
    of String: yellow "\"" & elem.str & "\""

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

defineCommands(ShellCommands, shellDocumentation, runShell):
  Exit = "exit"; "Exits interactive stacklang":
    echo ""
    quit 0
  History = "history"; "Prints out the entire command history so far":
    echo ""
    for i, command in commandHistory[0..^2]:
      stdout.write i, ": ", command, (if i != commandHistory.len - 2: "\n" else: "")
  Help = "help"; "Prints out all documentation":
    var customTable: TerminalTable
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
    stdout.write "\n"
    let padding = ' '.repeat(3)
    for category in calc.documentation.keys:
      for name, line in documentationLines(category):
        if name == a:
          stdout.write line.join padding
    for category in calc.documentation.keys:
      if category == a:
        var help: TerminalTable
        for _, line in documentationLines(category):
          help.add line
        if help.rows > 0:
          help.echoTable(padding = 3)
  Display = (a, "display"); "Shows the element on top off the stack without poping it":
    stdout.write "\n" & $a
    calc.stack.push a
  Print = (a, "print"); "Takes a number of things or a label to go back to, then prints those things in FIFO order with space separators":
    case a.kind:
    of Number:
      var pos = if a.num.int >= 0:
        calc.stack.len - a.num.int
      else:
        abs(a.num.int)
      if pos >= 0:
        var msg = ""
        while calc.stack.len > pos:
          msg.insert(($calc.stack.pop) & " ")
        stdout.write "\n" & msg
    of Label:
      var pos = calc.stack.high
      while calc.stack[pos].kind != Label or calc.stack[pos].lbl != a.lbl:
        pos -= 1
      pos += 1
      var msg = ""
      while calc.stack.len > pos:
        msg.insert(($calc.stack.pop) & " ")
      stdout.write "\n" & msg
    else: discard

calc.registerCommandRunner runShell, ShellCommands, "Interactive shell", shellDocumentation


template raiseInputError(msg, argument: string): untyped =
  var e = newException(InputError, msg)
  e.input = argument
  raise e

calc.registerCommandRunner(proc (calc: Calc, argument: string): Option[iterator() {.closure.}] =
  if argument[0] == '!':
    some(iterator() {.closure.} =
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
  else:
    some(iterator() {.closure.} =
      calc.stack.pushValue argument.Token))

proc colorize(x: seq[Rune]): seq[Rune] {.gcsafe.} =
  for part in ($x).tokenize(withWhitespace = true):
    if part.string.isEmptyOrWhitespace == true:
      result &= toRunes(part.string)
    else:
      result &= toRunes(case part.toElement().kind:
        of Label:
          if calc.isCommand(part):
            if calc.customCommands.hasKey(part.string):
              italic bold part.string
            else:
              bold part.string
          else:
            part.string
        of Number: blue part.string
        of String: yellow part.string
      )

var p = Prompt.init(promptIndicator = "> ", colorize = colorize)
p.showPrompt()

while true:
  let
    input = p.readLine()
    tokens = tokenize(input)
  commandHistory.add tokens
  let backup = deepCopy calc
  try:
    for token in tokens:
      calc.evaluateToken(token)
    calc.execute()
  except ArgumentError as e:
    echo red("\nError consuming element #", e.currentCommand.elems.len, ": "), e.currentCommand.elems[^1], red ", in command: ", bold e.currentCommand.name
    stdout.write red e.msg
    calc = backup
    commandHistory.setLen commandHistory.len - 1
  except InputError as e:
    echo red("\nError with input: "), e.input
    stdout.write red e.msg
    calc = backup
    commandHistory.setLen commandHistory.len - 1

  if calc.stack.len != 0:
    echo ""
    stdout.write "[ " &  calc.stack.map(`$`).join("  ") & " ]"
  echo ""
  var indicator = ""
  for awaiting in calc.awaitingCommands:
    indicator &= "["
    for argument in awaiting.elems:
      indicator &= $argument & " "
    indicator &= awaiting.name.bold & "] "
  p.setIndicator(indicator & "> ")
