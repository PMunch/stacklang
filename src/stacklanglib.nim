import math, strutils, npeg, tables, hashes, options

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
  Argument = enum AString = "s", ALabel = "l", ANumber = "n", AAny = "a"
  Documentation* = object
    msg*: string
    arguments*: seq[Argument]
  Token* = distinct string
  Stack*[T] = seq[T]
  Calc* = ref object
    commandRunners: seq[CommandRunner]
    stack*: Stack[Element]
    awaitingCommands*: seq[Command]
    customCommands*: Table[string, seq[Element]]
    #tmpCommands*: Table[string, seq[string]]
    #variables*: Table[string, Stack[Element]]
    #randoms*: seq[string]
    #messages: seq[seq[Message]]
  Command* = ref object
    name*: string
    exec*: iterator()
    elems*: seq[Element]
  StackLangError* = object of CatchableError
  InputError* = object of StackLangError
    input*: string
  ArgumentError* = object of StackLangError
    currentCommand*: Command
  CommandRunner* = proc (calc: Calc, argument: string): Option[iterator() {.closure.}]


template push*[T](stack: var Stack[T], value: T) =
  stack.add value

template pop*(calc: Calc): Element =
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

proc runCommand*(calc: Calc, command: string): Option[iterator() {.closure.}]

proc evaluateToken*(calc: Calc, token: Token) =
  if calc.customCommands.hasKey(token.string):
    for element in calc.customCommands[token.string]:
      case element.kind:
      of Number, String: calc.stack.add element
      of Label:
        if element.lbl[0] != '\\':
          calc.evaluateToken(Token(element.lbl))
        else:
          calc.stack.add Token(element.lbl[1..^1]).toElement
  else:
    calc.awaitingCommands.add new Command
    calc.awaitingCommands[^1].name = token.string
    calc.awaitingCommands[^1].exec = block:
      var command: Option[iterator() {.closure.}]
      for runner in calc.commandRunners:
        command = calc.runner(token.string)
        if command.isSome: break
      command.get
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

include operations
proc isCommand*(calc: Calc, cmd: Token): bool

proc `==`*(a, b: Element): bool =
  if a.kind == b.kind:
    return case a.kind:
    of Label: a.lbl == b.lbl
    of Number: a.num == b.num
    of String: a.str == b.str

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
    discard a
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
  Until = (a, l, "until"); "Takes a label or a length and runs the given command until the stack is that length or the label is the topmost element":
    if not calc.isCommand(b.Token):
      var e = newException(InputError, "Label is not a command")
      e.input = b
      raise e
    var iterationsLeft = 100_000
    template runIteration() =
      calc.evaluateToken(b.Token)
      dec iterationsLeft
      if iterationsLeft == 0:
        raise newException(StackLangError, "Until ran for too many iterations")
    case a.kind:
    of Number:
      while calc.stack.len.float != a.num:
        runIteration()
    of Label, String:
      while true:
        if calc.stack.len == 0: yield
        if calc.stack[^1] == a: break
        runIteration()
  MakeCommand = (a, "mkcmd"); "Takes a label or a position and creates a command of everything from that position to the end of the stack":
    case a.kind:
    of Label:
      var pos = calc.stack.find(a)
      if pos != -1:
        calc.customCommands[a.lbl] = calc.stack[pos+1 .. ^1]
        calc.stack.setLen(pos+1)
    else: discard
  Call = (l, "call"); "Calls the given label as a command":
    calc.evaluateToken(a.Token) #iterator() {.closure.} =
    #  discard # Should be an error
    #)

proc isCommand*(calc: Calc, cmd: Token): bool =
  try:
    discard parseEnum[Commands](cmd.string)
    true
  except:
    calc.customCommands.hasKey cmd.string

proc newCalc*(): Calc =
  new result
  result.commandRunners.add runCommand

proc registerCommandRunner*(calc: Calc, commandRunner: CommandRunner) =
  calc.commandRunners.add commandRunner
