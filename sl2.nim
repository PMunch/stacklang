import prompt, strutils

type
  Operations = enum Add = "+", Subtract = "-", Multiply = "*", Divide = "/", TriDivide = "//", Pop = "pop", Exit = "exit"
  Command = ref object
    name: string
    exec: iterator()
    elems: seq[float]

var
  stack: seq[float]
  blocked: seq[Command]

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
  for cmd in commands:
    try:
      let f = parseFloat(cmd)
      stack.add f
    except:
      try:
        closureScope:
          var command = new Command
          command.name = cmd
          let c = parseEnum[Operations](cmd)
          command.exec = case c:
            of Add:
              (iterator () {.closure.} =
                let a = stack.pop("+")
                let b = stack.pop("+(" & $a & ")")
                stack.add a+b)
            of Subtract:
              (iterator () {.closure.} =
                let a = stack.pop("-")
                let b = stack.pop("-(" & $a & ")")
                stack.add a-b)
            of Multiply:
              (iterator () {.closure.} =
                let a = stack.pop("*")
                let b = stack.pop("*(" & $a & ")")
                stack.add a*b)
            of Divide:
              (iterator () {.closure.} =
                let a = stack.pop("/")
                let b = stack.pop("/(" & $a & ")")
                stack.add a/b)
            of TriDivide:
              (iterator () {.closure.} =
                let a = stack.pop("")
                let b = stack.pop("")
                let c = stack.pop("")
                stack.add a/b/c)
            of Pop:
              (iterator () {.closure.} =
                discard stack.pop("pop"))
            of Exit:
              (iterator () {.closure.} =
                echo ""
                quit 0)
          command.exec()
          if not command.exec.finished:
            blocked.add command
      except:
        echo "\nInvalid command: ", cmd
  while stack.len != 0 and blocked.len != 0:
    var i = blocked[blocked.high]
    blocked.setLen(blocked.len-1)
    i.exec()
    if not i.exec.finished:
      blocked.add i
  stdout.write "\n"
  for i in blocked:
    stdout.write i.name & "(" & i.elems.join(", ") & ")" & " "
  echo stack

