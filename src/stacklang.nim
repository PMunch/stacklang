import stacklanglib
import prompt, strutils

var p = Prompt.init(promptIndicator = "> ")
p.showPrompt()

while true:
  let
    input = p.readLine()
    commands = input.splitWhitespace()

  echo commands
