import math, strutils, tables, os, random, sequtils
import operations
export operations.StackError
import termstyle

type
  ElementKind* = enum String, Float
  Element* = object
    case kind*: ElementKind
    of String:
      strVal*: string
    of Float:
      floatVal*: float
  MessageComponents* = enum Text, Tab, Elem
  Message* = object
    case kind*: MessageComponents
    of Text:
      strVal*: string
    of Elem:
      elem*: Element
    else: discard
  Stack*[T] = seq[T]
  Calc* = ref object
    stack*: Stack[Element]
    customCommands*: Table[string, seq[string]]
    tmpCommands*: Table[string, seq[string]]
    variables*: Table[string, Stack[Element]]
    randoms*: seq[string]
    messages: seq[seq[Message]]

template `&=`(messages: var seq[seq[Message]], message: seq[Message]) =
  messages.add message

template `!`(x: string or Element): untyped =
  when x is Element:
    Message(kind: Elem, elem: x)
  else:
    if x == "\t":
      Message(kind: Tab)
    else:
      Message(kind: Text, strVal: x)

proc `&=`(messages: var seq[seq[Message]], message: string) =
  messages.add(message.split(Newlines).mapIt(Message(kind: Text, strVal: it)))

proc `$`*(element: Element): string =
  case element.kind:
  of Float: $element.floatVal.formatFloat(ffDefault, -1)
  of String: $element.strVal

#template humanEcho*(args: varargs[string, `$`]) =
#  if isatty(stdin):
#    echo(join args)

template debug(args: varargs[string, `$`]) =
  when defined(verbosedebug):
    let output = join args
    if output[0..2] != "dbg":
      echo gray "dbg: ", output
    else:
      echo gray output

template push*[T](stack: var Stack[T], value: T) =
  stack.add value

proc `$`*[T](stack: Stack[T]): string =
  result = "["
  for elem in stack:
    result &= $elem & "  "
  result.setLen(max(result.len - 1, 2))
  result[^1] = ']'

# Convenience template to execute an operation over two operands from the stack
template execute[T](stack: var Stack[T], operation: untyped): untyped {.dirty.} =
  if stack[^1].kind != Float:
    raise newException(ValueError, "Expected two floats but x is not a float: " & $stack[^1])
  elif stack[^2].kind != Float:
    raise newException(ValueError, "Expected two floats but y is not a float: " & $stack[^2])
  else:
    let
      a = stack[^1].floatVal
      b = stack[^2].floatVal
    stack.setLen(stack.len - 2)
    stack.push(Element(kind: Float, floatVal: float(operation)))

template simpleExecute[T](stack: var seq[T], operation: untyped): untyped {.dirty.} =
  if stack[^1].kind != Float:
    raise newException(ValueError, "Expected a float but x is not a float: " & $stack[^1])
  else:
    let a = stack.pop.floatVal
    stack.push(Element(kind: Float, floatVal: float(operation)))

template toElem(x: float): Element =
  Element(kind: Float, floatVal: x)

template toElem(x: string): Element =
  try:
    Element(kind: Float, floatVal: parseFloat(x))
  except:
    Element(kind: String, strVal: x)

template perform(calc: Calc, action: untyped): untyped =
  calc.stack.push toElem(action)

# Then define all our commands using our macro
defineCommands(Commands, docstrings, signatures, runCommand):
  Ampersand = (a, a, "&"); "Combines two items into one":
    let nlbl = $a & $b
    calc.stack.push toElem(nlbl)
  Plus = (n, n, "+"); "Adds two numbers":
    #calc.stack.execute(a + b)
    calc.perform a + b
  Minus = (n, n, "-"); "Subtract two numbers":
    calc.perform a - b
  Multiply = (n, n, "*"); "Multiplies two numbers":
    calc.perform a * b
  Divide = (n, n, "/"); "Divides two numbers":
    calc.perform a / b
  Sqrt = (n, "sqrt"); "Takes the square root of a number":
    calc.perform sqrt(a)
  Power = (n, n, "^"); "Takes one number and raises it to the power of another":
    calc.perform a.pow(b)
  Sine = "sin"; "Takes the sine of a number":
    calc.stack.simpleExecute(sin(a))
  HyperSine = "sinh"; "Takes the hyperbolic sine of a number":
    calc.stack.simpleExecute(sinh(a))
  ArcSine = "arcsin"; "Takes the arc sine of a number":
    calc.stack.simpleExecute(arcsin(a))
  InvHyperSine = "arcsinh"; "Takes the inverse hyperbolic sine of a number":
    calc.stack.simpleExecute(arcsinh(a))
  Cosine = "cos"; "Takes the cosine of a number":
    calc.stack.simpleExecute(cos(a))
  HyperCosine = "cosh"; "Takes the hyperbolic cosine of a number":
    calc.stack.simpleExecute(cosh(a))
  ArcCosine = "arccos"; "Takes the arc cosine of a number":
    calc.stack.simpleExecute(arccos(a))
  InvHyperCosine = "arccosh"; "Takes the inverse hyperbolic cosine of a number":
    calc.stack.simpleExecute(arccosh(a))
  Tangent = "tan"; "Takes the tangent of a number":
    calc.stack.simpleExecute(tan(a))
  HyperTangent = "tanh"; "Takes the hyperbolic tangent of a number":
    calc.stack.simpleExecute(tanh(a))
  ArcTangent = "arctan"; "Takes the arc tangent of a number":
    calc.stack.simpleExecute(arctan(a))
  InvHyperTangent = "arctanh"; "Takes the inverse hyperbolic tangent of a number":
    calc.stack.simpleExecute(arctanh(a))
  DegToRad = "dtr"; "Converts a number from degrees to radians":
    calc.stack.simpleExecute(degToRad(a))
  RadToDeg = "rtd"; "Converts a number from radians to degrees":
    calc.stack.simpleExecute(radToDeg(a))
  Modulo = "mod"; "Takes the modulo of one number over another":
    calc.stack.execute(b mod a)
  Binom = "binom"; "Computes the binomial coefficient":
    calc.stack.execute(binom(b.int, a.int))
  Factorial = "fac"; "Computes the factorial of a non-negative number":
    calc.stack.simpleExecute(fac(a.int))
  NatLogarithm = "ln"; "Computes the natural logarithm of a number":
    calc.stack.simpleExecute(ln(a))
  Logarithm = "log"; "Computes the logarithm of the first number to the base of the second":
    calc.stack.execute(log(b, a))
  Pop = "pop"; "Pops an element off the stack.and discards it":
    discard calc.stack.pop
  Display = "display"; "Shows the element on top off the stack without poping it":
    calc.messages &= $calc.stack[^1] & "\n"
  Print = "print"; "Takes a number of things, then prints those things in FIFO order with space separators":
    let lbl = calc.stack[^1]
    calc.stack.setLen(calc.stack.len - 1)
    case lbl.kind:
    of Float:
      if lbl.floatVal.int >= 0:
        calc.messages &= calc.stack[lbl.floatVal.int .. ^1].map(`$`).join " "
        calc.stack.setLen(lbl.floatVal.int)
      else:
        calc.messages &= calc.stack[calc.stack.len + lbl.floatVal.int .. ^1].map(`$`).join " "
        calc.stack.setLen(calc.stack.len + lbl.floatVal.int)
    of String:
      var pos = calc.stack.high
      while calc.stack[pos].kind != String or calc.stack[pos].strVal != lbl.strVal:
        pos -= 1
      calc.messages &= calc.stack[pos + 1 .. ^1].map(`$`).join " "
      calc.stack.setLen(pos)
  StackSwap = "swap"; "Swaps the two bottom elements on the stack":
    let
      a = calc.stack[^1]
      b = calc.stack[^2]
    calc.stack[^1] = b
    calc.stack[^2] = a
  StackRotate = "rot"; "Rotates the stack one level":
    calc.stack.insert(calc.stack.pop, 0)
  StackInsert = "insert"; "Takes an element and a number and inserts the element at that position in the stack":
    let
      el = calc.stack[^2]
      pos = calc.stack[^1]
    calc.stack.setLen(calc.stack.len - 2)
    case pos.kind:
    of Float:
      if pos.floatVal.int >= 0:
        calc.stack.insert(el, pos.floatVal.int)
      else:
        calc.stack.insert(el, calc.stack.len + pos.floatVal.int)
    of String:
      var cpos = calc.stack.high
      while calc.stack[cpos].kind != String or calc.stack[cpos].strVal != pos.strVal:
        cpos -= 1
      calc.stack.insert(el, cpos + 1)
  Delete = "delete"; "Deletes the element of the stack at a given position":
    let pos = calc.stack.pop
    case pos.kind:
    of Float:
      if pos.floatVal.int >= 0:
        calc.stack.delete(pos.floatVal.int)
      else:
        calc.stack.delete(calc.stack.high + pos.floatVal.int + 1)
    of String:
      var cpos = calc.stack.high
      while calc.stack[cpos].kind != String or calc.stack[cpos].strVal != pos.strVal:
        cpos -= 1
      calc.stack.delete(cpos + 1)
  StackLen = "len"; "Puts the length of the stack onto the stack":
      calc.stack.push Element(kind: Float, floatVal: calc.stack.len.float)
  RandLabel = "rand"; "Creates a random label that's guaranteed to not collide":
    var cmdname = "rand" & align($rand(9999), 4, '0')
    while cmdname in calc.customCommands or cmdname in calc.tmpCommands or cmdname in calc.variables:
      cmdname = "rand" & align($rand(9999), 4, '0')
    calc.stack.push Element(kind: String, strVal: cmdname)
    calc.randoms.push cmdname
  RandLast = "lstrand"; "Pops the last random label off an internal stack and puts it on the actual stack":
      calc.stack.push Element(kind: String, strVal: calc.randoms.pop)
  Until = "until"; "Takes a label and a command and runs the command until the topmost element on the stack is the label":
    let
      lbl = calc.stack[^2]
      cmd = calc.stack[^1].strVal
    var iterationsLeft = 100_000
    let expandedCommand =
      calc.customCommands.getOrDefault(cmd, calc.tmpCommands.getOrDefault(cmd))
    if calc.tmpCommands.hasKey cmd:
      calc.tmpCommands.del cmd
    calc.stack.setLen(calc.stack.len - 2)
    if expandedCommand.len > 0:
      debug "Running custom command \"", expandedCommand.join(" "), "\" until hitting label ", lbl
    else:
      debug "Running built-in command \"", cmd, "\" until hitting label ", lbl
    case lbl.kind:
    of Float:
      if lbl.floatVal.int >= 0:
        var runLast = false
        while calc.stack.len != lbl.floatVal.int and not runLast:
          if calc.stack.len == lbl.floatVal.int + 1:
            runLast = true
          if expandedCommand.len > 0:
            discard calc.execute(expandedCommand)
          else:
            calc.runCmd(cmd)
          iterationsLeft -= 1
          if iterationsLeft == 0:
            raise newException(ValueError, "Iteration ran more than 100 000 times, aborting")
      else:
        let prelen = calc.stack.len
        var runLast = false
        while calc.stack.len != prelen + lbl.floatVal.int and not runLast:
          if calc.stack.len == lbl.floatVal.int + 1:
            runLast = true
          if expandedCommand.len > 0:
            discard calc.execute(expandedCommand)
          else:
            calc.runCmd(cmd)
          iterationsLeft -= 1
          if iterationsLeft == 0:
            raise newException(ValueError, "Iteration ran more than 100 000 times, aborting")
    of String:
      while calc.stack[^1].kind != String or calc.stack[^1].strVal != lbl.strVal:
        if expandedCommand.len > 0:
          discard calc.execute(expandedCommand)
        else:
          calc.runCmd(cmd)
        iterationsLeft -= 1
        if iterationsLeft == 0:
          raise newException(ValueError, "Iteration ran more than 100 000 times, aborting")
  VariablePush = "varpush"; "Takes an element and a label and pushes the element to the stack named by the label":
    if calc.stack[^1].kind != String:
      raise newException(ValueError, "Last element on stack must be a label")
    else:
      if calc.variables.hasKey(calc.stack[^1].strVal):
        calc.variables[calc.stack[^1].strVal].add calc.stack[^2]
      else:
        calc.variables[calc.stack[^1].strVal] = @[calc.stack[^2]]
      calc.stack.setLen(calc.stack.len - 2)
  VariablePop = "varpop"; "Takes a label and pops an element of the stack named by that label":
    if calc.stack[^1].kind != String:
      raise newException(ValueError, "Last element on stack must be a label")
    else:
      let label = calc.stack[^1].strVal
      if not calc.variables.hasKey(label):
        raise newException(ValueError, "No variable named " & label)
      else:
        calc.stack[^1] = calc.variables[label].pop
        if calc.variables[label].len == 0:
          calc.variables.del label
  VariableMerge = "varmrg"; "Takes a label and puts all elements of that variable onto the current stack, deleting the variable":
    if calc.stack[^1].kind != String:
      raise newException(ValueError, "Last element on stack must be a label")
    else:
      let label = calc.stack.pop.strVal
      if not calc.variables.hasKey(label):
        raise newException(ValueError, "No variable named " & label)
      else:
        calc.stack = calc.stack.concat calc.variables[label]
        calc.variables.del label
  VariableSwap = "varswp"; "Takes a label and swaps the current stack for that of the one named by that label":
    if calc.stack[^1].kind != String:
      raise newException(ValueError, "Last element on stack must be a label")
    else:
      let
        label = calc.stack.pop.strVal
        oldStack = calc.stack
      if calc.variables.hasKey(label):
        calc.stack = calc.variables[label]
      else:
        calc.stack = @[]
      if oldStack.len != 0:
        calc.variables[label] = oldStack
      else:
        if calc.variables.hasKey(label):
          calc.variables.del label
  VariableDelete = "vardel"; "Takes a label and deletes the variable by that name":
    if calc.stack[^1].kind != String:
      raise newException(ValueError, "Last element on stack must be a label")
    else:
      let label = calc.stack.pop.strVal
      calc.variables.del label
  ListVariables = "list"; "Lists all currently stored variables":
    for key, value in calc.variables:
      calc.messages &= @[!toElem(key), !"\t"].concat(value.mapIt(!it))
  Dup = "dup"; "Duplicates the last element on the stack":
    calc.stack.push calc.stack[^1]
  Nop = "nop"; "Does nothing":
    discard
  MakeCommand = "mkcmd"; "Takes a label or an index and turns everything up to that point into a command, if\n\t\tgiven a label that label will be used as the name, otherwise it will be assigned a randomly generated one that will be pushed to the stack":
    let
      lbl = calc.stack[^1]
    calc.stack.setLen(calc.stack.len - 1)
    case lbl.kind:
    of Float:
      var newcmd: seq[string]
      if lbl.floatVal.int >= 0:
        newcmd = calc.stack[lbl.floatVal.int .. ^1].map(`$`)
        calc.stack.setLen(lbl.floatVal.int)
      else:
        newcmd = calc.stack[calc.stack.len + lbl.floatVal.int .. ^1].map(`$`)
        calc.stack.setLen(calc.stack.len + lbl.floatVal.int)
      var cmdname = "tmp" & align($rand(9999), 4, '0')
      while cmdname in calc.customCommands or cmdname in calc.tmpCommands:
        cmdname = "tmp" & align($rand(9999), 4, '0')
      calc.tmpCommands[cmdname] = newcmd
      calc.stack.push Element(kind: String, strVal: cmdname)
    of String:
      var pos = calc.stack.high
      while calc.stack[pos].kind != String or calc.stack[pos].strVal != lbl.strVal:
        pos -= 1
      calc.customCommands[lbl.strVal] = calc.stack[pos + 1 .. ^1].map(`$`)
      calc.stack.setLen(pos)
      #calc.stack.push Element(kind: String, strVal: lbl.strVal)
  ExpandCommand = "excmd"; "Takes a label and puts the elements of a coresponding command onto the stack":
    let
      cmdName = calc.stack.pop.strVal
      cmd =  if calc.customCommands.hasKey cmdName: calc.customCommands[cmdName]
        else: calc.tmpCommands[cmdName]
    for command in cmd:
      calc.pushValue(command)
  DeleteCommand = "delcmd"; "Deletes the command given by the last label":
    let cmdName = calc.stack.pop.strVal
    if calc.customCommands.hasKey cmdName:
      calc.customCommands.del cmdName
    elif calc.tmpCommands.hasKey cmdName:
      calc.tmpCommands.del cmdName
    else:
      debug "No custom command with name ", cmdName, " found"
    #  raise newException(ValueError, "No custom command with name " & cmdName & " found")
  ListCommands = "lscmd"; "Lists all the custom commands":
    if calc.customCommands.len > 0:
      calc.messages &= "These are the currently defined custom commands:\n"
      for name, command in calc.customCommands.pairs:
        calc.messages &= @[!"\t", !toElem(name), !"->", !"\t"].concat(command.mapIt(!toElem(it)))
    if calc.tmpCommands.len > 0:
      calc.messages &= "These are the temporary commands:\n"
      for name, command in calc.tmpCommands.pairs:
        calc.messages &= @[!"\t", !toElem(name), !"->", !"\t"].concat(command.mapIt(!toElem(it)))
#      humanEcho calc.stack
#    verbose = false
  Call = "call"; "Takes a label and runs it as a command":
      if calc.stack[^1].kind != String:
        raise newException(ValueError, "Call take a string")
      else:
        calc.runCmd(calc.stack.pop.strVal)
  Name = "name"; "Takes a label, and a label to a custom command and renames the command to the first label":
    let
      name = calc.stack[^2].strVal
      cmd = calc.stack[^1].strVal
    calc.stack.setLen(calc.stack.len - 2)
    try:
      discard parseEnum[Commands](name)
      raise newException(ValueError, "Command name can't be one of the built-in commands")
    except:
      if calc.customCommands.hasKey cmd:
        calc.customCommands[name] = calc.customCommands[cmd]
        calc.customCommands.del cmd
      elif calc.tmpCommands.hasKey cmd:
        calc.customCommands[name] = calc.tmpCommands[cmd]
        calc.tmpCommands.del cmd
  Help = "help"; "Lists all the commands with documentation":
    calc.messages &= "Commands:\n"
    for command in Commands:
      if signatures[command].len == 0:
        calc.messages &= @[!"\t", !toElem($command), !"\t", !docstrings[command]]
      else:
        calc.messages &= @[!"\t", !toElem($command), !("[" & signatures[command].join(" ") & "]"), !"\t", !docstrings[command]]
    calc.messages &= "When running a series of commands you can also use these:\n"
    for command in InternalCommands:
      if signaturesInternal[command].len == 0:
        calc.messages &= @[!"\t", !toElem($command), !"\t", !docstringsInternal[command]]
      else:
        calc.messages &= @[!"\t", !toElem($command), !("[" & signaturesInternal[command].join(" ") & "]"), !"\t", !docstringsInternal[command]]
  Exit = "exit"; "Exits the program, saving custom commands":
    var output = open(getAppDir() / "stacklang.custom", fmWrite)
    for name, command in calc.customCommands.pairs:
      output.writeLine(command.join(" ") & " " & name)
    output.close()
    quit 0

defineCommands(InternalCommands, docstringsInternal, signaturesInternal, runInternalCommand):
  GotoBackward = "goback"; "Goes to the first instance of a label within a command":
    try:
      let destination = calc.stack.pop
      case destination.kind:
      of String:
        let label = destination.strVal
        labelGotos.inc(label)
        debug("increased label ", label, " to ", labelGotos[label])
        i = cc.find(label)
      of Float:
        let pos = destination.floatVal.int
        if pos >= 0:
          i = pos
        else:
          i += pos - 1
      calc.runCmdCmd(cc, i, labelGotos)
    except:
      echo getCurrentExceptionMsg()
      raise
  GotoForward = "gofwd"; "Goes to the last instance of a label within a command":
    try:
      let destination = calc.stack.pop
      case destination.kind:
      of String:
        let label = destination.strVal
        labelGotos.inc(label)
        debug("increased label ", label, " to ", labelGotos[label])
        for x in countdown(cc.high, cc.low):
          if cc[x] == label:
            i = x + 1
            break
      of Float:
        let pos = destination.floatVal.int
        if pos >= 0:
          i = cc.high - pos
        else:
          i -= pos
      calc.runCmdCmd(cc, i, labelGotos)
    except:
      echo getCurrentExceptionMsg()
      raise
  LessThan = "<"; "Compares two elements and if a<b it runs the next command, otherwise the second next command":
    debug "dbg(<): ", calc.stack
    calc.stack.compare(`<`)
  MoreThan = ">"; "Compares two elements and if a>b it runs the next command, otherwise the second next command":
    calc.stack.compare(`>`)
  Equal = "="; "Compares two elements and if a=b it runs the next command, otherwise the second next command":
    calc.stack.compare(`==`)
  NotEqual = "!="; "Compares two elements and if a!=b it runs the next command, otherwise the second next command":
    calc.stack.compare(`!=`)
  LessOrEqual = "<="; "Compares two elements and if a<=b it runs the next command, otherwise the second next command":
    calc.stack.compare(`<=`)
  MoreOrEqual = ">="; "Compares two elements and if a>=b it runs the next command, otherwise the second next command":
    calc.stack.compare(`>=`)
  LabelCount = "lblcnt"; "Takes a label and puts the amount of times that label has been the target of goback or gofwd in this run of the command":
    debug "dbg(lblcnt): ", labelGotos.getOrDefault(calc.stack[^1].strVal, 0)
    debug "dbg(lblcnt): ", calc.stack
    calc.stack.push Element(kind: Float, floatVal: labelGotos.getOrDefault(calc.stack.pop().strVal, 0).float)
    i += 1
    calc.runCmdCmd(cc, i, labelGotos)

template compare[T](stack: var Stack[T], operation: untyped): untyped {.dirty.} =
  let
    a = stack[^2]
    b = stack[^1]
  stack.setLen(stack.len - 2)
  if a.kind != b.kind:
    raise newException(ValueError, "Can't compare " & $a & " to " & $b & " since they are of different types")
  else:
    let condition =
      if a.kind == Float:
        operation(a.floatVal, b.floatVal)
      else:
        operation(a.strVal, b.strVal)
    if condition: #operation(a.floatVal, b.floatVal):
      i += 1
      let oldi = i
      calc.runCmdCmd(cc, i, labelGotos)
      if i == oldi:
        i += 1
    else:
      i += 2
      calc.runCmdCmd(cc, i, labelGotos)

proc runCmd(calc: Calc, command: string, verbose = false)

proc runCmdCmd(calc: Calc, cc: seq[string], i: var int, labelGotos: var CountTable[string]) =
  runInternalCommand(cc[i]):
    if cc.high >= i:
      calc.runCmd(cc[i])
    #else:
    #  raise newException(ValueError, $i & " not in " & $cc)

proc cleanTmp(calc: Calc, cmd: string): bool =
  var hasTmp = false
  debug "trying to clean temporary command " & cmd
  block findTmp:
    for e in calc.stack:
      if e.kind == String and e.strVal == cmd:
        debug "\tfound on stack, not removing"
        hasTmp = true
        break findTmp
    for c in calc.customCommands.values:
      if cmd in c:
        debug "\tfound in custom command, not removing"
        hasTmp = true
        break findTmp
    for k in calc.tmpCommands.keys:
      if cmd != k and cmd in calc.tmpCommands[k]:
        debug "\tfound in other temporary command \"" & k & "\", not removing"
        hasTmp = true
        break findTmp
    for k in calc.variables.keys:
      for e in calc.variables[k]:
        if e.kind == String and e.strVal == cmd:
          debug "\tfound in variable stack \"" & k & "\", not removing"
          hasTmp = true
          break findTmp
  if not hasTmp:
    calc.tmpCommands.del cmd
    return true

proc execute*(calc: Calc, commands: seq[string]): seq[seq[Message]] =
  var
    labelGotos = initCountTable[string]()
    i = commands.low
  while i <= commands.high:
    debug "running cmd ", commands[i], "(", i, ")"
    debug "stack before run ", calc.stack
    calc.runCmdCmd(commands, i, labelGotos)
    debug "stack after run ", calc.stack
    i += 1
    for cmd in calc.tmpCommands.keys:
      discard calc.cleanTmp(cmd)
  result = calc.messages
  calc.messages = @[]

proc pushValue(calc: Calc, value: string) =
  case value:
  of "pi":
    calc.stack.push Element(kind: Float, floatVal: Pi)
  of "tau":
    calc.stack.push Element(kind: Float, floatVal: Tau)
  of "e":
    calc.stack.push Element(kind: Float, floatVal: E)
  else:
    try:
      calc.stack.push Element(kind: Float, floatVal: parseFloat(value))
    except:
      if value[0] == '\\':
        calc.stack.push Element(kind: String, strVal: value[1..^1])
      else:
        calc.stack.push Element(kind: String, strVal: value)

proc runCmd(calc: Calc, command: string, verbose = false) =
  var verbose = verbose
  runCommand(command):
    if calc.customCommands.hasKey(command):
      calc.messages &= calc.execute calc.customCommands[command]
    elif calc.tmpCommands.hasKey(command):
      let cmd = calc.tmpCommands[command]
      calc.messages &= calc.execute cmd
      discard calc.cleanTmp command
    else:
      calc.pushValue(command)
  if verbose:
    calc.messages &= $calc.stack & " <- " & command & "\n"
