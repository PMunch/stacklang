import stacklanglib
import prompt, unicode, termstyle
import strutils except tokenize

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

  for token in tokens:
    calc.evaluateToken(token):
      if token.string == "exit":
        quit 0
      calc.stack.pushValue(token)
  calc.execute()

  echo "\n", calc.stack, " | ", calc.awaitingCommands.len
