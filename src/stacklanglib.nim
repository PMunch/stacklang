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
  Argument* = enum AString = "s", ALabel = "l", ANumber = "n", AAny = "a"
  Documentation* = object
    msg*: string
    arguments*: seq[set[Argument]]
  Token* = distinct string
  Stack*[T] = seq[T]
  Calc* = ref object
    commandRunners: seq[CommandRunner]
    stack*: Stack[Element]
    awaitingCommands*: seq[Command]
    customCommands*: Table[string, seq[Element]]
    documentation*: OrderedTable[string, OrderedTable[string, Documentation]]
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

proc `$`(x: Element): string =
  result = "Element(kind: " & $x.kind & ", "
  case x.kind:
  of Label: result &= "lbl: " & x.lbl
  of String: result &= "str: " & x.str
  of Number: result &= "num: " & $x.num & ", encoding: " & $x.encoding
  result &= ")"

template push*[T](stack: var Stack[T], value: T) =
  stack.add value

template pop*(calc: Calc): Element =
  block:
    if calc.stack.len == 0:
      yield
    calc.awaitingCommands[^1].elems.add calc.stack[^1]
    calc.stack.setLen calc.stack.len - 1
    calc.awaitingCommands[^1].elems[^1]

template peek*(calc: Calc): Element =
  block:
    if calc.stack.len == 0:
      yield
    calc.stack[^1]

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

template calculate(command: untyped): untyped =
  calc.stack.push(Element(kind: Number, num: float(command), encoding: a_encoding))

defineCommands(MathCommands, mathDocumentation, runMath):
  Plus = (n, n, "+"); "Adds two numbers":
    calculate a + b
  Minus = (n, n, "-"); "Subtract two numbers":
    calculate a - b
  Multiply = (n, n, "*"); "Multiplies two numbers":
    calculate a * b
  Divide = (n, n, "/"); "Divides two numbers":
    calculate a / b
  Sqrt = (n, "sqrt"); "Takes the square root of a number":
    calculate sqrt(a)
  Power = (n, n, "^"); "Takes one number and raises it to the power of another":
    calculate b.pow(a)
  Sine = (n, "sin"); "Takes the sine of a number":
    calculate sin(a)
  HyperSine = (n, "sinh"); "Takes the hyperbolic sine of a number":
    calculate sinh(a)
  ArcSine = (n, "arcsin"); "Takes the arc sine of a number":
    calculate arcsin(a)
  InvHyperSine = (n, "arcsinh"); "Takes the inverse hyperbolic sine of a number":
    calculate arcsinh(a)
  Cosine = (n, "cos"); "Takes the cosine of a number":
    calculate cos(a)
  HyperCosine = (n, "cosh"); "Takes the hyperbolic cosine of a number":
    calculate cosh(a)
  ArcCosine = (n, "arccos"); "Takes the arc cosine of a number":
    calculate arccos(a)
  InvHyperCosine = (n, "arccosh"); "Takes the inverse hyperbolic cosine of a number":
    calculate arccosh(a)
  Tangent = (n, "tan"); "Takes the tangent of a number":
    calculate tan(a)
  HyperTangent = (n, "tanh"); "Takes the hyperbolic tangent of a number":
    calculate tanh(a)
  ArcTangent = (n, "arctan"); "Takes the arc tangent of a number":
    calculate arctan(a)
  InvHyperTangent = (n, "arctanh"); "Takes the inverse hyperbolic tangent of a number":
    calculate arctanh(a)
  DegToRad = (n, "dtr"); "Converts a number from degrees to radians":
    calculate degToRad(a)
  RadToDeg = (n, "rtd"); "Converts a number from radians to degrees":
    calculate radToDeg(a)
  Modulo = (n, n, "mod"); "Takes the modulo of one number over another":
    calculate a mod b
  Binom = (n, n, "binom"); "Computes the binomial coefficient":
    calculate binom(a.int, b.int)
  Factorial = (n, "fac"); "Computes the factorial of a non-negative number":
    calculate fac(a.int)
  NatLogarithm = (n, "ln"); "Computes the natural logarithm of a number":
    calculate ln(a)
  Logarithm = (n, n, "log"); "Computes the logarithm of the first number to the base of the second":
    calculate log(a, b)

defineCommands(StackCommands, stackDocumentation, runStack):
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
  Len = "len"; "Puts the length of the stack on the stack":
    calc.stack.push(Element(kind: Number, num: calc.stack.len.float))
  #StackInsert = (a, a, "insert"); "Takes an element and a number and inserts the element at that position in the stack":
  #  let
  #    el = calc.stack[^2]
  #    pos = calc.stack[^1]
  #  calc.stack.setLen(calc.stack.len - 2)
  #  case pos.kind:
  #  of Float:
  #    if pos.floatVal.int >= 0:
  #      calc.stack.insert(el, pos.floatVal.int)
  #    else:
  #      calc.stack.insert(el, calc.stack.len + pos.floatVal.int)
  #  of String:
  #    var cpos = calc.stack.high
  #    while calc.stack[cpos].kind != String or calc.stack[cpos].strVal != pos.strVal:
  #      cpos -= 1
  #    calc.stack.insert(el, cpos + 1)
  #Delete = "delete"; "Deletes the element of the stack at a given position":
  #  let pos = calc.stack.pop
  #  case pos.kind:
  #  of Float:
  #    if pos.floatVal.int >= 0:
  #      calc.stack.delete(pos.floatVal.int)
  #    else:
  #      calc.stack.delete(calc.stack.high + pos.floatVal.int + 1)
  #  of String:
  #    var cpos = calc.stack.high
  #    while calc.stack[cpos].kind != String or calc.stack[cpos].strVal != pos.strVal:
  #      cpos -= 1
  #    calc.stack.delete(cpos + 1)

defineCommands(Commands, documentation, runCommand):
  Hex = (n, "hex"); "Converts a number to hex encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Hexadecimal))
  Bin = (n, "bin"); "Converts a number to binary encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Binary))
  Dec = (n, "dec"); "Converts a number to decimal encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Decimal))
  Until = (l|n, l, "until"); "Takes a label or a length and runs the given command until the stack is that length or the label is the topmost element":
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
  MakeCommand = (n|l, "mkcmd"); "Takes a label or a position and creates a command of everything from that position to the end of the stack":
    case a.kind:
    of Label:
      var newCmd: seq[Element]
      while calc.peek.kind != Label or calc.peek.lbl != a.lbl:
        newCmd.add calc.pop()
      calc.customCommands[a.lbl] = newCmd
    else: discard
  Call = (l, "call"); "Calls the given label as a command":
    calc.evaluateToken(a.Token) #iterator() {.closure.} =
    #  discard # Should be an error
    #)

proc isCommand*(calc: Calc, cmd: Token): bool =
  calc.customCommands.hasKey(cmd.string) or (block:
    for category, commands in calc.documentation:
      for command in commands.keys:
        if command == cmd.string:
          return true
    false)

proc newCalc*(): Calc =
  new result

proc registerCommandRunner*(calc: Calc, commandRunner: CommandRunner) =
  calc.commandRunners.add commandRunner

proc registerCommandRunner*(calc: Calc, commandRunner: CommandRunner, commands: typedesc[enum], documentationCategory: string, documentation: openArray[Documentation]) =
  calc.commandRunners.add commandRunner
  if documentation.len != 0:
    if not calc.documentation.hasKey documentationCategory:
      calc.documentation[documentationCategory] = initOrderedTable[string, Documentation]()
    for cmd in commands:
      calc.documentation[documentationCategory][$cmd] = documentation[cmd.int]

proc registerDefaults*(calc: Calc) =
  calc.registerCommandRunner runMath, MathCommands, "Math", mathDocumentation
  calc.registerCommandRunner runCommand, Commands, "Other", documentation
  calc.registerCommandRunner runStack, StackCommands, "Stack", stackDocumentation
