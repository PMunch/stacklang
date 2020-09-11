import math, strutils, npeg

type
  ElementKind* = enum String, Label, Number
  Encoding* = enum Decimal, Binary, Hexadecimal
  Element* = object
    case kind*: ElementKind
    of Label:
      lbl*: string
    of String:
      str*: string
    of Number:
      encoding*: Encoding
      num*: float
  Argument = enum AString, ALabel, ANumber, AAny
  Documentation = object
    msg: string
    arguments: seq[Argument]
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
  StackLangError* = object of CatchableError
  InputError* = object of StackLangError
    input: string
  ArgumentError* = object of StackLangError
    currentCommand*: Command

include operations

defineCommands(Commands, documentation, runCommand):
  Plus = (n, n, "+"); "Adds two numbers":
    calc.stack.push(Element(kind: Number, num: a + b, encoding: a_encoding))
  Minus = (n, n, "-"); "Subtract two numbers":
    calc.stack.push(Element(kind: Number, num: a - b, encoding: a_encoding))
  Multiply = (n, n, "*"); "Multiplies two numbers":
    calc.stack.push(Element(kind: Number, num: a * b, encoding: a_encoding))
  Divide = (n, n, "/"); "Divides two numbers":
    calc.stack.push(Element(kind: Number, num: a / b, encoding: a_encoding))
  Pop = (a, "pop"); "Pops an element off the stack, discarding it":
    discard
  Dup = (a, "dup"); "Duplicates the topmost element on the stack":
    calc.stack.push(a)
    calc.stack.push(a)
  Swap = (a, a, "swap"); "Swaps the two topmost elements of the stack":
    calc.stack.push b
    calc.stack.push a
  Rot = (a, "rot"); "Rotates the stack, putting the topmost element on the bottom":
    calc.stack.insert a
  Hex = (n, "hex"); "Converts a number to hex encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Hexadecimal))
  Bin = (n, "bin"); "Converts a number to binary encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Binary))
  Dec = (n, "dec"); "Converts a number to decimal encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Decimal))
  Len = "len"; "Puts the length of the stack on the stack":
    calc.stack.push(Element(kind: Number, num: calc.stack.len.float))

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

template labelVerify(x: string) =
  if x.contains ' ':
    var e = newException(InputError, "Label cannot contain spaces")
    e.input = x
    raise e

proc pushLabel*(stack: var Stack[Element], x: string) =
  x.labelVerify
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
      elif value.string[0] == '0':
        case value.string[1]
        of 'x':
          if value.string.len == 2:
            Element(kind: Number, num: 0.0, encoding: Hexadecimal)
          else:
            Element(kind: Number, num: parseHexInt(value.string).float, encoding: Hexadecimal)
        of 'b':
          if value.string.len == 2:
            Element(kind: Number, num: 0.0, encoding: Binary)
          else:
            Element(kind: Number, num: parseBinInt(value.string).float, encoding: Binary)
        else:
          var e = newException(InputError, "Unknown encoding")
          e.input = value.string
          raise e

      else:
        value.string.labelVerify
        if value.string[0] == '\\':
          Element(kind: Label, lbl: value.string[1..^1])
        else:
          Element(kind: Label, lbl: value.string)

proc pushValue*(stack: var Stack[Element], value: Token) =
  stack.push value.toElement

template stepCommand*(command: Command) =
  command.exec()

template evaluateToken*(calc: Calc, token: Token, elseBlock: untyped) =
  calc.awaitingCommands.add new Command
  calc.awaitingCommands[^1].name = token.string
  calc.awaitingCommands[^1].exec = runCommand(token.string):
    elseBlock
  calc.awaitingCommands[^1].stepCommand()
  if calc.awaitingCommands[^1].exec.finished:
    calc.awaitingCommands.setLen calc.awaitingCommands.len - 1

template execute*(calc: Calc) =
  while calc.stack.len != 0 and calc.awaitingCommands.len != 0:
    var i = calc.awaitingCommands[calc.awaitingCommands.high]
    i.stepCommand()
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
