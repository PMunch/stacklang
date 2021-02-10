import math, strutils, npeg, tables, hashes, options, random, sequtils

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
    tmpCommands*: Table[string, seq[Element]]
    variables*: Table[string, Stack[Element]]
    #randoms*: seq[string]
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

template raiseInputError(msg, argument: string): untyped =
  var e = newException(InputError, msg)
  e.input = argument
  raise e

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
          value.string.labelVerify
          Element(kind: Label, lbl: value.string)

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
  template doTok() =
    case element.kind:
    of Number, String: calc.stack.add element
    of Label:
      if element.lbl[0] != '\\':
        calc.evaluateToken(Token(element.lbl))
      else:
        calc.stack.add Token(element.lbl[1..^1]).toElement
  if calc.customCommands.hasKey(token.string):
    for element in calc.customCommands[token.string]:
      doTok()
  elif calc.tmpCommands.hasKey(token.string):
    for element in calc.tmpCommands[token.string]:
      doTok()
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

template untilPosition(a: Element, action: untyped): untyped =
  case a.kind:
  of Label:
    while calc.peek.kind != Label or calc.peek.lbl != a.lbl:
      action
  of Number:
    var
      consumeLen = a.num.int
      consumed = 0
    if consumeLen >= 0:
      consumeLen = calc.stack.len - consumeLen
    else:
      consumeLen = abs(consumeLen)
    if consumeLen <= 0:
      var e = newException(ArgumentError, [
        "Can't run with no arguments",
        "Current stack position is lower than requested stopping point"
        ][consumeLen.abs.min(1)])
      e.currentCommand = calc.awaitingCommands[^1]
      raise e
    while consumed != consumeLen:
      action
      consumed += 1
  else: discard

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
    calculate a.pow(b)
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
  StackInsert = (a, n|l, "insert"); "Takes an element and a position and inserts the element before that position in the stack":
    # This is a weird way of doing this which doesn't really work with waiting commands
    var tail: seq[Element]
    untilPosition(b):
      tail.insert calc.pop()
    calc.stack.push a
    calc.stack &= tail[0..^1]
  Delete = (n|l, "delete"); "Deletes the element of the stack at a given position":
    var tail: seq[Element]
    untilPosition(a):
      tail.insert calc.pop()
    calc.stack &= tail[1..^1]

defineCommands(VariableCommands, variableDocumentation, runVariable):
  VariablePush = (a, l, "varpush"); "Takes an element and a label and pushes the element to the stack named by the label":
    calc.variables.mgetOrPut(b, @[]).add a
  VariablePop = (l, "varpop"); "Takes a label and pops an element of the stack named by that label":
    if not calc.variables.hasKey(a):
      raise newException(ValueError, "No variable named " & a)
    else:
      calc.stack.push calc.variables[a].pop
      if calc.variables[a].len == 0:
        calc.variables.del a
  VariableMerge = (l, "varmrg"); "Takes a label and puts all elements of that variable onto the current stack, deleting the variable":
    if not calc.variables.hasKey(a):
      raise newException(ValueError, "No variable named " & a)
    else:
      calc.stack = calc.stack.concat calc.variables[a]
      calc.variables.del a
  VariableSwap = (l, "varswp"); "Takes a label and swaps the current stack for that of the one named by that label":
    let oldStack = calc.stack
    calc.stack = calc.variables.getOrDefault(a)
    if oldStack.len != 0:
      calc.variables[a] = oldStack
    else:
      if calc.variables.hasKey(a):
        calc.variables.del a
  VariableDelete = (l, "vardel"); "Takes a label and deletes the variable by that name":
    calc.variables.del a

defineCommands(BitCommands, bitDocumentation, runBits):
  And = (n, n, "and"); "Runs a binary and operation on two numbers":
    calculate a.int and b.int
  Or = (n, n, "or"); "Runs a binary or operation on two numbers":
    calculate a.int or b.int
  Not = (n, "not"); "Runs a binary not operation on two numbers":
    calculate not a.int
  ShiftLeft = (n, n, "shl"); "Shift a number left by the given amount":
    calculate a.int shl b.int
  ShiftRight = (n, n, "shr"); "Shift a number right by the given amount":
    calculate a.int shr b.int
  Truncate (n, n, "trunc"); "Truncates a binary number":
    calculate a.int and ((0b1 shl b.int) - 1)

defineCommands(Commands, documentation, runCommand):
  Hex = (n, "hex"); "Converts a number to hex encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Hexadecimal))
  Bin = (n, "bin"); "Converts a number to binary encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Binary))
  Dec = (n, "dec"); "Converts a number to decimal encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Decimal))
  Nop = "nop"; "Does nothing":
    discard
  Until = (l|n, l, "until"); "Takes a label or a length and runs the given command until the stack is that length or the label is the topmost element. If the label is parseable as a number it can also be used to run until a number is on top":
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
    of Label:
      let numeral = try: (num: parseFloat(a.lbl), i: true) except: (num: 0.0, i: false)
      while true:
        if calc.stack.len == 0: yield
        if calc.stack[^1] == a: break
        if numeral.i and calc.stack[^1].kind == Number and calc.stack[^1].num == numeral.num: break
        runIteration()
    else: discard
  MakeCommand = (n|l, "mkcmd"); "Takes a label or a position and creates a command of everything from that position to the end of the stack":
    var newCmd: seq[Element]
    untilPosition(a):
      newCmd.insert calc.pop()
    case a.kind:
    of Label:
      calc.customCommands[a.lbl] = newCmd
      calc.documentation["Custom"][a.lbl] = Documentation(msg: "", arguments: @[])
    of Number:
      var name = "tmp" & align($rand(9999), 4, '0')
      while calc.customCommands.hasKey(name) or calc.tmpCommands.hasKey(name):
        name = "tmp" & align($rand(9999), 4, '0')
      calc.tmpCommands[name] = newCmd
      calc.stack.pushValue name.Token
    else: discard
  DeleteCommand = (l, "delcmd"); "Takes a label and deletes the custom command by that name":
    if calc.customCommands.hasKey a:
      calc.documentation["Custom"].del a
      calc.customCommands.del a
    else:
      raiseInputError("No such command", a)
  NameCommand = (l, l, "name"); "Takes a label of a command and a label, names (or renames) the command to the label":
    if calc.tmpCommands.hasKey(a):
      calc.customCommands[b] = calc.tmpCommands[a]
      calc.documentation["Custom"][b] = Documentation(msg: "", arguments: @[])
      calc.tmpCommands.del a
    elif calc.customCommands.hasKey(a):
      calc.customCommands[b] = calc.customCommands[a]
      calc.customCommands.del a
    else:
      raiseInputError("No such command", a)
  DocumentCommand = (s, l, "doccmd"); "Takes a string and a label and documents the command by that name":
    if calc.customCommands.hasKey b:
      calc.documentation["Custom"][b].msg = a
    else:
      raiseInputError("No such command", b)
  Call = (l, "call"); "Calls the given label as a command":
    if calc.isCommand a.Token:
      calc.evaluateToken(a.Token)
    else:
      raiseInputError("No such command", a)
  ExpandCommand = (l, "excmd"); "Expands the given command onto the stack":
    if calc.customCommands.hasKey(a) or calc.tmpCommands.hasKey(a):
      for elem in calc.customCommands[a]:
        calc.stack.push elem
      for elem in calc.tmpCommands[a]:
        calc.stack.push elem
    else:
      raiseInputError("No such command", a)
  DropWaiting = "dropwait"; "Drops the last command waiting for input":
    calc.awaitingCommands[^2] = calc.awaitingCommands[^1]
    calc.awaitingCommands.setLen calc.awaitingCommands.len - 1

proc isCommand*(calc: Calc, cmd: Token): bool =
  calc.customCommands.hasKey(cmd.string) or
  calc.tmpCommands.hasKey(cmd.string) or (block:
    for category, commands in calc.documentation:
      for command in commands.keys:
        if command == cmd.string:
          return true
    false)

proc newCalc*(): Calc =
  new result
  result.documentation["Custom"] = initOrderedTable[string, Documentation]()

proc registerCommandRunner*(calc: Calc, commandRunner: CommandRunner) =
  calc.commandRunners.add commandRunner

proc registerCommandRunner*(calc: Calc, commandRunner: CommandRunner, commands: typedesc[enum], documentationCategory: string, documentation: openArray[Documentation]) =
  assert not calc.documentation.hasKey documentationCategory, "Category " & documentationCategory & " is already registered"
  calc.commandRunners.add commandRunner
  if documentation.len != 0:
    calc.documentation[documentationCategory] = initOrderedTable[string, Documentation]()
    for cmd in commands:
      calc.documentation[documentationCategory][$cmd] = documentation[cmd.int]

proc registerDefaults*(calc: Calc) =
  calc.registerCommandRunner runMath, MathCommands, "Math", mathDocumentation
  calc.registerCommandRunner runBits, BitCommands, "Bitwise", bitDocumentation
  calc.registerCommandRunner runCommand, Commands, "Other", documentation
  calc.registerCommandRunner runStack, StackCommands, "Stack", stackDocumentation
  calc.registerCommandRunner runVariable, VariableCommands, "Variable", variableDocumentation
