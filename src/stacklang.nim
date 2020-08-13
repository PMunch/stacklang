import stacklanglib
import prompt, unicode, termstyle
import strutils except tokenize
import sequtils, math

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

proc `$`(elem: Element): string =
  case elem.kind:
    of Label:
      if elem.lbl.Token.isCommand: bold elem.lbl else: elem.lbl
    of Number: blue elem.presentNumber
    of String: yellow "\"" & elem.str & "\""

proc colorize(x: seq[Rune]): seq[Rune] {.gcsafe.} =
  for part in ($x).tokenize(withWhitespace = true):
    if part.string.isEmptyOrWhitespace == true:
      result &= toRunes(part.string)
    else:
      result &= toRunes(case part.toElement().kind:
        of Label:
          if part.isCommand: bold part.string else: part.string
        of Number: blue part.string
        of String: yellow part.string
      )

var
  calc = newCalc()
  p = Prompt.init(promptIndicator = "> ", colorize = colorize)
p.showPrompt()

while true:
  let
    input = p.readLine()
    tokens = tokenize(input)
  let backup = deepCopy calc
  try:
    for token in tokens:
      calc.evaluateToken(token):
        if token.string == "exit":
          echo ""
          quit 0
        calc.stack.pushValue(token)
    calc.execute()
  except ArgumentError as e:
    echo red("\nError consuming element #", e.currentCommand.elems.len, ": "), e.currentCommand.elems[^1], red(", in command: ", e.currentCommand.name)
    stdout.write red e.msg
    calc = backup

  echo ""
  stdout.write calc.stack.map(`$`).join "  "
  stdout.write " | " & $calc.awaitingCommands.len
  echo ""
