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
  Token = distinct string
  Stack*[T] = seq[T]
  Calc* = ref object
    stack*: Stack[Element]
    currentCommand*: Command
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
  Plus = "+"; "Adds two numbers":
    calc.stack.push(Element(kind: Number, num: calc.pop().num + calc.pop().num))
  Minus = "-"; "Subtract two numbers":
    calc.stack.push(Element(kind: Number, num: -calc.pop().num + calc.pop().num))
  Multiply = "*"; "Multiplies two numbers":
    calc.stack.push(Element(kind: Number, num: calc.pop().num * calc.pop().num))
  Divide = "/"; "Divides two numbers":
    let
      a = calc.pop().num
      b = calc.pop().num
    calc.stack.push(Element(kind: Number, num: b / a))

proc newCalc*(): Calc =
  new result

template push*[T](stack: var Stack[T], value: T) =
  stack.add value

template pop*(calc: var Calc): Element =
  block:
    if calc.stack.len == 0:
      yield
    calc.currentCommand.elems.add calc.stack[^1]
    calc.stack.setLen calc.stack.len - 1
    calc.currentCommand.elems[^1]

proc pushNumber*(stack: var Stack[Element], x: float) =
  stack.push Element(kind: Number, num: x)

proc pushString*(stack: var Stack[Element], x: string) =
  stack.push Element(kind: String, str: x)

proc pushLabel*(stack: var Stack[Element], x: string) =
  assert not x.contains ' ', "Label cannot contain spaces"
  stack.push Element(kind: Label, lbl: x)

proc pushValue*(stack: var Stack[Element], value: Token) =
  case value.string:
  of "pi":
    stack.push Element(kind: Number, num: Pi)
  of "tau":
    stack.push Element(kind: Number, num: Tau)
  of "e":
    stack.push Element(kind: Number, num: E)
  else:
    try:
      stack.push Element(kind: Number, num: parseFloat(value.string))
    except:
      if value.string[0] == '"':
        stack.push Element(kind: String, str: value.string[1..^2])
      else:
        assert not value.string.contains ' ', "Label cannot contain spaces"
        if value.string[0] == '\\':
          stack.push Element(kind: Label, lbl: value.string[1..^1])
        else:
          stack.push Element(kind: Label, lbl: value.string)

template evaluateToken*(calc: Calc, token: Token, elseBlock: untyped) =
  calc.currentCommand = new Command
  calc.currentCommand.name = token.string
  calc.currentCommand.exec = runCommand(token.string):
    elseBlock

let parser = peg "tokens":
  nonquoted <- ('\\' * '"') | (1-'"')
  quoted <- >('"' * *nonquoted * '"')
  token <- quoted | >(+Graph)
  tokens <- +(token * ?' ')

proc tokenize*(input: string): seq[Token] =
  seq[Token](parser.match(input).captures)
