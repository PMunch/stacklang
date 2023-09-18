import math, strutils, npeg, tables, hashes, options, random, sequtils
import mapm
export mapm

type
  ElementKind* = enum String, Label, Number
  Encoding* = enum Decimal, Scientific, Binary, Hexadecimal
  Element* = object
    case kind*: ElementKind
    of Label:
      lbl*: string
    of String:
      str*: string
    of Number:
      encoding*: Encoding
      num*: Mapm
  Argument* = enum AString = "s", ALabel = "l", ANumber = "n", AAny = "a"
  Documentation* = object
    msg*: string
    arguments*: seq[set[Argument]]
  Token* = distinct string
  Stack*[T] = seq[T]
  Calc* = ref object
    commandRunners*: seq[CommandRunner]
    stack*: Stack[Element]
    customCommands*: Table[string, seq[Element]]
    documentation*: OrderedTable[string, OrderedTable[string, Documentation]]
    tmpCommands*: Table[string, seq[Element]]
    variables*: Table[string, Stack[Element]]
    noEvalUntil*: string
    commandEvalStack*: seq[tuple[name, label: string, idx: int, labelCounts: CountTable[string]]]
    #randoms*: seq[string]
  StackLangError* = object of CatchableError
  InputError* = object of StackLangError
    input*: string
  ArgumentError* = object of StackLangError
    currentCommand*: string
    currentElement*: Element
  StackEmptyError* = object of StackLangError
  CommandRunner* = proc (calc: Calc, argument: string): bool

template raiseInputError(msg, argument: string): untyped =
  var e = newException(InputError, msg)
  e.input = argument
  raise e

proc newArgumentError(msg, command: string, element: Element): ref ArgumentError =
  result = newException(ArgumentError, msg)
  result.currentCommand = command
  result.currentElement = element

proc `$`(x: Element): string =
  result = "Element(kind: " & $x.kind & ", "
  case x.kind:
  of Label: result &= "lbl: " & x.lbl
  of String: result &= "str: " & x.str
  of Number: result &= "num: " & $x.num & ", encoding: " & $x.encoding
  result &= ")"

template push*[T](stack: var Stack[T], value: T) =
  stack.add value

proc pop*(calc: Calc): Element =
  if calc.stack.len == 0:
    raise newException(StackEmptyError, "The stack didn't have sufficient elements")
  result = calc.stack[^1]
  calc.stack.setLen calc.stack.len - 1

template peek*(calc: Calc): Element =
  block:
    if calc.stack.len == 0:
      raise newException(StackEmptyError, "The stack didn't have sufficient elements")
    calc.stack[^1]

proc pushNumber*(stack: var Stack[Element], x: Mapm) =
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
    Element(kind: Number, num: MM_Pi)
  of "tau":
    Element(kind: Number, num: MM_2Pi)
  of "e":
    Element(kind: Number, num: MM_E)
  else:
    try:
      if (value.string.len == 1 and value.string[0].isDigit) or
        (value.string.allCharsInSet(Digits + {'e', '-', '+', '.', '_'}) and not value.string.allCharsInSet({'e', '-', '+', '.', '_'})):
        Element(kind: Number, num: initMapm(value.string.replace("_", "")))
      else: raise newException(ValueError, "Invalid number")
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
            Element(kind: Number, num: MMzero, encoding: Hexadecimal)
          else:
            Element(kind: Number, num: parseHexInt(value.string).initMapm, encoding: Hexadecimal)
        of 'b':
          if value.string.len == 2:
            Element(kind: Number, num: MMzero, encoding: Binary)
          else:
            Element(kind: Number, num: parseBinInt(value.string).initMapm, encoding: Binary)
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

proc evaluateToken*(calc: Calc, token: Token) =
  if calc.noEvalUntil.len != 0:
    if token.string == calc.noEvalUntil:
      calc.noEvalUntil.setLen 0
    else:
      if token.string[0] == '\\':
        calc.stack.pushValue ("\\" & token.string).Token
      else:
        calc.stack.pushValue token
      return
  try:
    template executeCommand(command: untyped) =
      calc.commandEvalStack.add (token.string, "var_" & rand(int.high).toHex, 0, initCountTable[string]())
      while calc.commandEvalStack[^1].idx <= command.high:
        let element = command[calc.commandEvalStack[^1].idx]
        case element.kind:
        of Number, String: calc.stack.add element
        of Label:
          if element.lbl[0] != '\\':
            calc.evaluateToken(Token(element.lbl))
          else:
            calc.stack.add Token(element.lbl[1..^1]).toElement
        calc.commandEvalStack[^1].idx += 1
      calc.commandEvalStack.setLen calc.commandEvalStack.len - 1
    if calc.customCommands.hasKey(token.string):
      executeCommand(calc.customCommands[token.string])
    elif calc.tmpCommands.hasKey(token.string):
      executeCommand(calc.tmpCommands[token.string])
    else:
      for runner in calc.commandRunners:
        if calc.runner(token.string): break
  except MapmError as e:
    var ex = newException(StackLangError, "Error executing math operation: " & e.msg)
    ex.parent = e
    raise ex
  # TODO: Clean temporary commands?

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

proc getCurrentCommand*(calc: Calc): seq[Element] =
  if calc.customCommands.hasKey(calc.commandEvalStack[^1].name):
    calc.customCommands[calc.commandEvalStack[^1].name]
  elif calc.tmpCommands.hasKey(calc.commandEvalStack[^1].name):
    calc.tmpCommands[calc.commandEvalStack[^1].name]
  else: raise newException(StackLangError, "Current command not found in list of commands")

proc `==`*(a, b: Element): bool =
  if a.kind == b.kind:
    return case a.kind:
    of Label: a.lbl == b.lbl
    of Number: a.num == b.num
    of String: a.str == b.str

template calculate(command: untyped): untyped =
  when typeof(command) is Mapm:
    calc.stack.push(Element(kind: Number, num: command, encoding: a_encoding))
  else:
    calc.stack.push(Element(kind: Number, num: initMapm(command), encoding: a_encoding))

template untilPosition(a: Element, action: untyped): untyped =
  case a.kind:
  of Label:
    var iterationsLeft = 100_000
    let numeral = try: (num: initMapm(a.lbl), i: true) except: (num: MMzero.Mapm, i: false)
    while calc.peek.kind != Label or calc.peek.lbl != a.lbl:
      if calc.peek.kind == Number and numeral.i and calc.peek.num == numeral.num:
        break
      action
      dec iterationsLeft
      if iterationsLeft == 0:
        raise newException(StackLangError, "Command ran for too many iterations")
  of Number:
    var
      consumeLen = a.num.toInt
      consumed = 0
    if consumeLen >= 0:
      consumeLen = calc.stack.len - consumeLen
    else:
      consumeLen = abs(consumeLen)
    if consumeLen == 0:
      var e = newException(ArgumentError, "Current stack position is already at requested position")
      e.currentCommand = command # Command comes from the defineCommands macro
      e.currentElement = a
      raise e
    elif consumeLen < 0:
      consumeLen = calc.stack.len + abs(consumeLen) - 1
    while consumed != consumeLen:
      action
      consumed += 1
  else: discard

proc getPosition(calc: Calc, a: Element, command: string): int =
  case a.kind:
  of Label:
    let numeral = try: (num: initMapm(a.lbl), i: true) except: (num: MMzero.Mapm, i: false)
    result = calc.stack.high
    while calc.stack[result].kind != Label or calc.stack[result].lbl != a.lbl:
      if numeral.i and calc.stack[result].kind == Number and calc.stack[result].num == numeral.num:
        break
      result -= 1
    result += 1
  of Number:
    let num = a.num.toInt
    if num >= 0:
      result = num
    else:
      result = calc.stack.len + num
    if result >= calc.stack.len:
      var e = newException(ArgumentError, [
        "Current stack position is already at requested position",
        "Current stack position is lower than requested position"
        ][min(result - calc.stack.len, 1)])
      e.currentCommand = command
      e.currentElement = a
      raise e
  else:
    var e = newException(ArgumentError, "Can't be called with a string")
    e.currentCommand = command
    e.currentElement = a
    raise e

defineCommands(MathCommands, mathDocumentation, runMath):
  Plus = (n, n, "+"); "Adds two numbers":
    calculate a + b
  Minus = (n, n, "-"); "Subtract two numbers":
    calculate a - b
  Multiply = (n, n, "*"); "Multiplies two numbers":
    calculate a * b
  Divide = (n, n, "/"); "Divides two numbers":
    if b == 0'm:
      raise newException(StackLangError, "Can't divide by 0")
    calculate divide(a, b)
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
    calculate binom(a, b)
  Factorial = (n, "fac"); "Computes the factorial of a non-negative number":
    calculate fac(a)
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
  Rot = ("rot"); "Rotates the stack, putting the bottommost element on top":
    if calc.stack.len != 0:
      calc.stack.push calc.stack[0]
      calc.stack.delete(0)
    else:
      raise newException(StackEmptyError, "The stack didn't have sufficient elements")
  ReverseRot = (a, "revrot"); "Rotates the stack, putting the topmost element on the bottom":
    calc.stack.insert a
  Len = "len"; "Puts the length of the stack on the stack":
    calc.stack.push(Element(kind: Number, num: calc.stack.len.initMapm))
  StackInsert = (a, n|l, "insert"); "Takes an element and a position and inserts the element before that position in the stack":
    let pos = calc.getPosition(b, command)
    calc.stack.insert(a, pos)
  Delete = (n|l, "delete"); "Deletes the element of the stack at a given position":
    let pos = calc.getPosition(a, command)
    calc.stack.delete(pos)
  Fetch = (n|l, "fetch"); "Takes the element of the stack at a given position and puts it on top":
    let pos = calc.getPosition(a, command)
    calc.stack.push calc.stack[pos]
    calc.stack.delete(pos)
  Position = (n|l, "pos"); "Puts the index of the position on the stack":
    var pos = calc.getPosition(a, command)
    if a.kind == Label: pos -= 1
    calc.stack.push(Element(kind: Number, num: pos.initMapm, encoding: Decimal))

defineCommands(VariableCommands, variableDocumentation, runVariable):
  VariablePush = (a, l, "varpush"); "Takes an element and a label and pushes the element to the stack named by the label":
    calc.variables.mgetOrPut(b, @[]).add a
  VariableTake = (n|l, l, "vartake"); "Takes a position and a label and moves elements from the stack to the variable until it's at the position":
    let pos = calc.getPosition(a, command)
    if calc.variables.hasKey(b):
      calc.variables[b] &= calc.stack[pos..^1]
    else:
      calc.variables[b] = calc.stack[pos..^1]
    calc.stack.setLen(pos)
  VariablePop = (l, "varpop"); "Takes a label and pops an element of the stack named by that label":
    if not calc.variables.hasKey(a):
      raiseInputError("No variable with this name", a)
    else:
      calc.stack.push calc.variables[a].pop
      if calc.variables[a].len == 0:
        calc.variables.del a
  VariableMerge = (l, "varmrg"); "Takes a label and puts all elements of that variable onto the current stack, deleting the variable":
    if not calc.variables.hasKey(a):
      raiseInputError("No variable with this name", a)
    else:
      calc.stack = calc.stack.concat calc.variables[a]
      calc.variables.del a
  VariableExpand = (l, "varexp"); "Takes a label and puts all elements of that variable onto the current stack":
    if not calc.variables.hasKey(a):
      raiseInputError("No variable with this name", a)
    else:
      calc.stack = calc.stack.concat calc.variables[a]
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
    calculate a.toInt and b.toInt
  Or = (n, n, "or"); "Runs a binary or operation on two numbers":
    calculate a.toInt or b.toInt
  Xor = (n, n, "xor"); "Runs a binary xor operation on two numbers":
    calculate a.toInt xor b.toInt
  Not = (n, "not"); "Runs a binary not operation on a number":
    calculate not a.toInt
  ShiftLeft = (n, n, "shl"); "Shift a number left by the given amount":
    calculate a.toInt shl b.toInt
  ShiftRight = (n, n, "shr"); "Shift a number right by the given amount":
    calculate a.toInt shr b.toInt
  Truncate (n, n, "truncbin"); "Truncates a binary number":
    calculate a.toInt and ((0b1 shl b.toInt) - 1)

defineCommands(ModificationCommands, modDocumentation, runModifications):
  Round = (n, "round"); "Rounds a number to the closest integer":
    calculate round(a)
  Ceil = (n, "ceil"); "Rounds a number up":
    calculate ceil(a)
  Floor = (n, "floor"); "Rounds a number down":
    calculate floor(a)
  Sgn = (n, "sgn"); "Returns -1 for negative numbers, 1 for positive, and 0 for 0":
    calculate sgn(a)
  SplitDecimal = (n, "splitdec"); "Takes a number and splits it into an integer and floating part":
    let (intp, flop) = splitDecimal(a)
    calc.stack.push Element(kind: Number, num: intp, encoding: a_encoding)
    calc.stack.push Element(kind: Number, num: flop, encoding: a_encoding)
  Trunc = (n, "trunc"); "Truncates the floating part off a number":
    calculate trunc(a)
  Clamp = (n, n, n, "clamp"); "Clamps a value in between two values":
    calculate clamp(a, b, c)

defineCommands(EncCommands, encDocumentation, runEncoding):
  Hex = (n, "hex"); "Converts a number to hex encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Hexadecimal))
  Bin = (n, "bin"); "Converts a number to binary encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Binary))
  Dec = (n, "dec"); "Converts a number to decimal encoding":
    calc.stack.push(Element(kind: Number, num: a, encoding: Decimal))
  Sci = (n, "sci"); "Converts a number to scientific notation":
    calc.stack.push(Element(kind: Number, num: a, encoding: Scientific))

template verifyCommand(): untyped =
  if calc.commandEvalStack.len == 0:
    raise newException(StackLangError, "Unable to run '" & command & "' outside of a command context")

defineCommands(Commands, documentation, runCommand):
  Nop = "nop"; "Does nothing":
    discard
  Rand = "rand"; "Adds a random number between 0 and 1 to the stack":
    calc.stack.push(Element(kind: Number, num: rand(), encoding: Decimal))
  NoEval = "noeval"; "Stops evaluation, all commands will simply be pushed to the stack":
    calc.noEvalUntil = "eval"
  NoEvalUntil = (l, "noevaluntil"); "Like noeval, but accepts a label which restarts execution before being evaluated":
    calc.noEvalUntil = a
  Eval = "eval"; "When noeval has been called, this will re-enable evaluation":
    discard
  Until = (l|n, l, "until"); "Takes a label or a position and runs the given command until the stack is that position":
    if not calc.isCommand(b.Token):
      raiseInputError("Label is not a command", b)
    untilPosition(a):
      calc.evaluateToken(b.Token)
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
      calc.documentation["Custom"][b] = calc.documentation["Custom"][a]
      calc.documentation["Custom"].del a
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
      if calc.customCommands.hasKey(a):
        for elem in calc.customCommands[a]:
          calc.stack.push elem
      if calc.tmpCommands.hasKey(a):
        for elem in calc.tmpCommands[a]:
          calc.stack.push elem
    else:
      raiseInputError("No such command", a)
  GoBack = (n|l, "goback"); "Takes a position in a command and moves back to that position":
    verifyCommand()
    let command = calc.getCurrentCommand()
    case a.kind:
    of Number:
      var n = a.num.toInt
      n =
        if n < 0: abs(n) - 1
        else: calc.commandEvalStack[^1].idx - n
      n -= 1
      if n < -1 or n > command.high:
        raise newArgumentError("Index out of range for current command", "goback", a)
      calc.commandEvalStack[^1].idx = n
    of Label:
      calc.commandEvalStack[^1].idx -= 2 # Go back before the argument
      while command[calc.commandEvalStack[^1].idx] != a:
        calc.commandEvalStack[^1].idx -= 1 # Search backwards
        if calc.commandEvalStack[^1].idx < 0:
          raise newArgumentError("Label not found earlier in the command", "goback", a)
      calc.commandEvalStack[^1].idx -= 1 # The index is incremented before the next loop, so go back one extra
      calc.commandEvalStack[^1].labelCounts.inc a.lbl
    else: discard
  GoForward = (n|l, "gofwd"); "Takes a position in a command and moves forward to that position":
    verifyCommand()
    let command = calc.getCurrentCommand()
    case a.kind:
    of Number:
      var n = a.num.toInt
      n =
        if n < 0: command.len + n
        else: calc.commandEvalStack[^1].idx + n
      n -= 1
      if n < -1 or n > command.high:
        raise newArgumentError("Index out of range for current command", "goback", a)
      calc.commandEvalStack[^1].idx = n
    of Label:
      calc.commandEvalStack[^1].idx += 1 # Go past the current command
      while command[calc.commandEvalStack[^1].idx] != a:
        calc.commandEvalStack[^1].idx += 1 # Search forwards
        if calc.commandEvalStack[^1].idx > command.high:
          raise newArgumentError("Label not found later in the command", "gofwd", a)
      calc.commandEvalStack[^1].idx -= 1 # The index is incremented before the next loop, so go back one extra
      calc.commandEvalStack[^1].labelCounts.inc a.lbl
    else: discard
  LabelCount = (l, "lblcnt"); "Puts the amount of times the given label has been jumped to by gofwd or goback onto the stack":
    verifyCommand()
    calc.stack.push(Element(kind: Number, num: initMapm(calc.commandEvalStack[^1].labelCounts[a]), encoding: Decimal))
  Return = ("return"); "Stops execution of the current command":
    verifyCommand()
    calc.commandEvalStack[^1].idx = int.high - 1
  CommandLabel = ("cmdlbl"); "Puts a label onto the stack, the label will be unique to each instance of a command":
    verifyCommand()
    calc.stack.push(Element(kind: Label, lbl: calc.commandEvalStack[^1].label))

template checkArgs(): untyped =
  if not calc.isCommand c.Token:
    raiseInputError("No such command", c)
  if not calc.isCommand d.Token:
    raiseInputError("No such command", d)

defineCommands(Conditionals, conditionalsDocumentation, runConditionals):
  LessThan = (n, n, l, l, "<"); "Takes two numbers and two labels, if the first number is smaller than the second runs the first label, otherwise runs the second label":
    checkArgs()
    if a < b:
      calc.evaluateToken(c.Token)
    else:
      calc.evaluateToken(d.Token)
  GreaterThan = (n, n, l, l, ">"); "Takes two numbers and two labels, if the first number is greater than the second runs the first label, otherwise runs the second label":
    checkArgs()
    if a > b:
      calc.evaluateToken(c.Token)
    else:
      calc.evaluateToken(d.Token)
  LessThanEq = (n, n, l, l, "<="); "Takes two numbers and two labels, if the first number is smaller than or equal to the second runs the first label, otherwise runs the second label":
    checkArgs()
    if a <= b:
      calc.evaluateToken(c.Token)
    else:
      calc.evaluateToken(d.Token)
  GreaterThanEq = (n, n, l, l, ">="); "Takes two numbers and two labels, if the first number is greater than or equal to the second runs the first label, otherwise runs the second label":
    checkArgs()
    if a >= b:
      calc.evaluateToken(c.Token)
    else:
      calc.evaluateToken(d.Token)
  Equal = (n, n, l, l, "=="); "Takes two numbers and two labels, if the numbers are equal runs the first label, otherwise runs the second label":
    checkArgs()
    if a == b:
      calc.evaluateToken(c.Token)
    else:
      calc.evaluateToken(d.Token)
  NotEqual = (n, n, l, l, "!="); "Takes two numbers and two labels, if the numbers are not equal runs the first label, otherwise runs the second label":
    checkArgs()
    if a != b:
      calc.evaluateToken(c.Token)
    else:
      calc.evaluateToken(d.Token)

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
  calc.registerCommandRunner runModifications, ModificationCommands, "Modifications", modDocumentation
  calc.registerCommandRunner runEncoding, EncCommands, "Encoding", encDocumentation
  calc.registerCommandRunner runCommand, Commands, "Other", documentation
  calc.registerCommandRunner runStack, StackCommands, "Stack", stackDocumentation
  calc.registerCommandRunner runVariable, VariableCommands, "Variable", variableDocumentation
  calc.registerCommandRunner runConditionals, Conditionals, "Conditionals", conditionalsDocumentation
