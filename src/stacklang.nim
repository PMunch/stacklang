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
    "0b" & n.num.int.toBin(64).strip(trailing = false, chars = {'0'})

var calc = newCalc()
calc.registerCommandRunner(proc (calc: Calc, argument: string): Option[iterator() {.closure.}] =
  if argument == "help":
    some(iterator() {.closure.} =
      stdout.write "\n"
      var help: TerminalTable
      for cmd in Commands:
        var arguments: string
        for i, argument in documentation[cmd].arguments:
          arguments &=
            (if i == 0: "" else: "") &
            $argument &
            (if i == documentation[cmd].arguments.high: "" else: ", ")
        help.add bold $cmd, arguments, documentation[cmd].msg
      help.echoTable(padding = 3))
  elif argument == "exit":
    some(iterator() {.closure.} =
      echo ""
      quit 0)
  else:
    some(iterator() {.closure.} =
      calc.stack.pushValue(argument.Token)))

proc `$`(elem: Element): string =
  case elem.kind:
    of Label:
      if calc.isCommand(elem.lbl.Token) or elem.lbl in ["help", "exit"]:
        if calc.customCommands.hasKey(elem.lbl):
          italic bold elem.lbl
        else:
          bold elem.lbl
      else:
        elem.lbl
    of Number: blue elem.presentNumber
    of String: yellow "\"" & elem.str & "\""

proc colorize(x: seq[Rune]): seq[Rune] {.gcsafe.} =
  for part in ($x).tokenize(withWhitespace = true):
    if part.string.isEmptyOrWhitespace == true:
      result &= toRunes(part.string)
    else:
      result &= toRunes(case part.toElement().kind:
        of Label:
          if calc.isCommand(part) or part.string in ["help", "exit"]:
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
  let backup = deepCopy calc
  try:
    for token in tokens:
      calc.evaluateToken(token)
    calc.execute()
  except ArgumentError as e:
    echo red("\nError consuming element #", e.currentCommand.elems.len + 1, ": "), e.currentCommand.elems[^1], red ", in command: ", bold e.currentCommand.name
    stdout.write red e.msg
    calc = backup
  except InputError as e:
    echo red("\nError with input: "), e.input
    stdout.write red e.msg
    calc = backup

  if calc.stack.len != 0:
    echo ""
    stdout.write calc.stack.map(`$`).join "  "
  echo ""
  var indicator = ""
  for awaiting in calc.awaitingCommands:
    indicator &= "["
    for argument in awaiting.elems:
      indicator &= $argument & " "
    indicator &= awaiting.name.bold & "] "
  p.setIndicator(indicator & "> ")
