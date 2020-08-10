import stacklanglib
import prompt, strutils

var
  calc = newCalc()
  p = Prompt.init(promptIndicator = "> ")
p.showPrompt()

while true:
  let
    input = p.readLine()
    commands = tokenize(input)

  for command in commands:
    calc.stack.pushValue(command)

  echo calc.stack
