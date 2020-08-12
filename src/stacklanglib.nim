import math, strutils, npeg, operations

type
  ElementKind* = enum String, Label, Number
  Element* = object
    case kind*: ElementKind
    of Label:
      lbl*: string
    of String:
      str*: string
    of Number:
      num*: float
  Token* = distinct string
  Stack*[T] = seq[T]
  Calc* = ref object
    stack*: Stack[Element]
    awaitingCommands*: seq[Command]
    #customCommands*: Table[string, seq[string]]
    #tmpCommands*: Table[string, seq[string]]
    #variables*: Table[string, Stack[Element]]
    #randoms*: seq[string]
    #messages: seq[seq[Message]]
  Command = ref object
    name*: string
    exec*: iterator()
    elems*: seq[Element]


defineCommands(Commands, Documentation, runCommand):
  Plus = (n, n, "+"); "Adds two numbers":
    calc.stack.push(Element(kind: Number, num: a + b))
  Minus = (n, n, "-"); "Subtract two numbers":
    calc.stack.push(Element(kind: Number, num: a - b))
  Multiply = (n, n, "*"); "Multiplies two numbers":
    calc.stack.push(Element(kind: Number, num: a * b))
  Divide = (n, n, "/"); "Divides two numbers":
    calc.stack.push(Element(kind: Number, num: a / b))
  Pop = "pop"; "Pops a number of the stack, discarding it":
    discard calc.pop()

proc newCalc*(): Calc =
  new result

template push*[T](stack: var Stack[T], value: T) =
  stack.add value

template pop*(calc: var Calc): Element =
  block:
    if calc.stack.len == 0:
      yield
    calc.awaitingCommands[^1].elems.add calc.stack[^1]
    calc.stack.setLen calc.stack.len - 1
    calc.awaitingCommands[^1].elems[^1]

proc pushNumber*(stack: var Stack[Element], x: float) =
  stack.push Element(kind: Number, num: x)

proc pushString*(stack: var Stack[Element], x: string) =
  stack.push Element(kind: String, str: x)

proc pushLabel*(stack: var Stack[Element], x: string) =
  assert not x.contains ' ', "Label cannot contain spaces"
  stack.push Element(kind: Label, lbl: x)

proc toElement*(value: Token): Element =
  case value.string:
  of "pi":
    Element(kind: Number, num: Pi)
  of "tau":
    Element(kind: Number, num: Tau)
  of "e":
    Element(kind: Number, num: E)
  else:
    try:
      Element(kind: Number, num: parseFloat(value.string))
    except:
      if value.string[0] == '"':
        if value.string[^1] == '"' and value.string.len > 1:
          Element(kind: String, str: value.string[1..^2])
        else:
          Element(kind: String, str: value.string[1..^1])
      else:
        assert not value.string.contains ' ', "Label cannot contain spaces"
        if value.string[0] == '\\':
          Element(kind: Label, lbl: value.string[1..^1])
        else:
          Element(kind: Label, lbl: value.string)

proc pushValue*(stack: var Stack[Element], value: Token) =
  stack.push value.toElement

template evaluateToken*(calc: Calc, token: Token, elseBlock: untyped) =
  calc.awaitingCommands.add new Command
  calc.awaitingCommands[^1].name = token.string
  calc.awaitingCommands[^1].exec = runCommand(token.string):
    elseBlock
  calc.awaitingCommands[^1].exec()
  if calc.awaitingCommands[^1].exec.finished:
    calc.awaitingCommands.setLen calc.awaitingCommands.len - 1

template execute*(calc: Calc) =
  while calc.stack.len != 0 and calc.awaitingCommands.len != 0:
    var i = calc.awaitingCommands[calc.awaitingCommands.high]
    i.exec()
    if i.exec.finished:
      calc.awaitingCommands.setLen(calc.awaitingCommands.len-1)

let
  parser = peg "tokens":
    nonquoted <- ('\\' * '"') | (1-'"')
    quoted <- >('"' * *nonquoted * ?'"')
    token <- quoted | >(+Graph)
    tokens <- +(token * *' ')
  wsparser = peg "wstokens":
    nonquoted <- ('\\' * '"') | (1-'"')
    quoted <- >('"' * *nonquoted * ?'"')
    token <- quoted | >(+Graph)
    whitespace <- >(*' ')
    wstokens <- +(token * whitespace)

proc tokenize*(input: string, withWhitespace = false): seq[Token] =
  if withWhitespace:
    seq[Token](wsparser.match(input).captures)
  else:
    seq[Token](parser.match(input).captures)

proc isCommand*(cmd: Token): bool =
  try:
    discard parseEnum[Commands](cmd.string)
    true
  except: false
