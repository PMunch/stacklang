import termstyle, prompt, strutils

var
  stack: seq[float]
  blocked: seq[tuple[name: string, exec: iterator(), elems: float]]

type Operations = enum Add = "+", Subtract = "-", Multiply = "*", Divide = "/", Pop = "pop", Exit = "exit"


var input = ""
var p = Prompt.init(promptIndicator = "> ")
p.showPrompt()

proc popImpl(stack: var seq[float]): float =
  result = stack[^1]
  stack.setLen stack.len-1

template pop(stack: var seq[float], name: string): float =
  block:
    if stack.len == 0:
      yield
    command.elems.add stack.popImpl()
    command.elems[^1]

while true:
  let input = p.readLine()
  let commands = input.splitWhitespace()
  for command in commands:
    try:
      let f = parseFloat(command)
      stack.add f
    except:
      try:
        let c = parseEnum[Operations](command)
        var i = case c:
          of Add:
            (iterator (): string {.closure.} =
              let a = stack.pop("+")
              let b = stack.pop("+(" & $a & ")")
              stack.add a+b)
          of Subtract:
            (iterator (): string {.closure.} =
              let a = stack.pop("-")
              let b = stack.pop("-(" & $a & ")")
              stack.add a-b)
          of Multiply:
            (iterator (): string {.closure.} =
              let a = stack.pop("*")
              let b = stack.pop("*(" & $a & ")")
              stack.add a*b)
          of Divide:
            (iterator (): string {.closure.} =
              let a = stack.pop("/")
              let b = stack.pop("/(" & $a & ")")
              stack.add a/b)
          of Pop:
            (iterator (): string {.closure.} =
              discard stack.pop("pop"))
          of Exit:
            (iterator (): string {.closure.} =
              echo ""
              quit 0)
        let name = i()
        if not i.finished:
          blocked.add (name: name, exec: i)
      except:
        echo "\nInvalid command: ", command
  while stack.len != 0 and blocked.len != 0:
    let i = blocked[blocked.high]
    blocked.setLen(blocked.len-1)
    let name = i.exec()
    if not i.exec.finished:
      blocked.add (name: name, exec: i.exec)
  stdout.write "\n"
  for i in blocked:
    stdout.write i.name & " "
  echo stack

