import stacklanglib
import prompt, strutils

var
  calc = newCalc()
  p = Prompt.init(promptIndicator = "> ")
p.showPrompt()

while true:
  let
    input = p.readLine()
    tokens = tokenize(input)

  for token in tokens:
    calc.evaluateToken(token):
      calc.stack.pushValue(token)
    calc.currentCommand.exec()

  echo calc.stack
