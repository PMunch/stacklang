import math, strutils, tables, os, terminal, random, sequtils
import rdstdin
import operations

type
  ElementKind = enum String, Float
  Element* = object
    case kind: ElementKind
    of String:
      strVal: string
    of Float:
      floatVal: float
  Stack[T] = seq[T]
  Calc* = ref object
    stack*: Stack[Element]
    customCommands*: Table[string, seq[string]]
    tmpCommands*: Table[string, seq[string]]
    variables*: Table[string, Element]
    randoms*: seq[string]
    messages: string

proc `$`*(element: Element): string =
  case element.kind:
  of Float: $element.floatVal
  of String: $element.strVal

#template humanEcho*(args: varargs[string, `$`]) =
#  if isatty(stdin):
#    echo(join args)

template debug(args: varargs[string, `$`]) =
  when defined(verbosedebug):
    let output = join args
    if output[0..2] != "dbg":
      echo "dbg: ", output
    else:
      echo output

template push[T](stack: var Stack[T], value: T) =
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

# Then define all our commands using our macro
defineCommands(Commands, docstrings, runCommand):
  Plus = "+"; "Adds two numbers":
    calc.stack.execute(a + b)
  Minus = "-"; "Subtract two numbers":
    calc.stack.execute(b - a)
  Multiply = "*"; "Multiplies two numbers":
    calc.stack.execute(a * b)
  Divide = "/"; "Divides two numbers":
    calc.stack.execute(b / a)
  Sqrt = "sqrt"; "Takes the square root of a number":
    calc.stack.simpleExecute(sqrt(a))
  Power = "^"; "Takes one number and raises it to the power of another":
    calc.stack.execute(b.pow(a))
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
    calc.messages &= "\n"
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
  Store = "store"; "Takes an element and a label and stores the element as a variable that can later be retrieved by load":
    if calc.stack[^1].kind != String:
      raise newException(ValueError, "Last element on stack must be a label")
    else:
      calc.variables[calc.stack[^1].strVal] = calc.stack[^2]
      calc.stack.setLen(calc.stack.len - 2)
  Load = "load"; "Takes a label and loads the variable by that name back onto the stack, removing the variable":
    if calc.stack[^1].kind != String:
      raise newException(ValueError, "Last element on stack must be a label")
    else:
      if not calc.variables.take(calc.stack[^1].strVal, calc.stack[^1]):
        raise newException(ValueError, "No variable named " & $calc.stack[^1])
  ListVariables = "list"; "Lists all currently stored variables":
    for key, value in calc.variables:
      echo key, "\t", value
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
      raise newException(ValueError, "No custom command with name " & cmdName & " found")
  ListCommands = "lscmd"; "Lists all the custom commands":
    if calc.customCommands.len > 0:
      calc.messages &= "These are the currently defined custom commands:\n"
      for name, command in calc.customCommands.pairs:
        calc.messages &= "\t" & name & "\t" & command.join(" ") & "\n"
    if calc.tmpCommands.len > 0:
      calc.messages &= "These are the temporary commands:\n"
      for name, command in calc.tmpCommands.pairs:
        calc.messages &= "\t" & name & "\t" & command.join(" ") & "\n"
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
      calc.messages &= "\t" & $command & "\t" & docstrings[command] & "\n"
    calc.messages &= "When running a series of commands you can also use these:\n"
    for command in InternalCommands:
      calc.messages &= "\t" & $command & "\t" & docstringsInternal[command] & "\n"
  Exit = "exit"; "Exits the program, saving custom commands":
    var output = open(getAppDir() / "stacklang.custom", fmWrite)
    for name, command in calc.customCommands.pairs:
      output.writeLine(command.join(" ") & " " & name)
    output.close()
    quit 0

defineCommands(InternalCommands, docstringsInternal, runInternalCommand):
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
  for e in calc.stack:
    if e.kind == String and e.strVal == cmd:
      hasTmp = true
      break
  for c in calc.customCommands.values:
    if cmd in c:
      hasTmp = true
      break
  for c in calc.tmpCommands.values:
    if cmd in c:
      hasTmp = true
      break
  if not hasTmp:
    calc.tmpCommands.del cmd
    return true

proc execute*(calc: Calc, commands: seq[string]): string =
  var
    labelGotos = initCountTable[string]()
    i = commands.low
  while i <= commands.high:
    debug "running cmd ", commands[i], "(", i, ")"
    debug "stack before run ", calc.stack
    calc.runCmdCmd(commands, i, labelGotos)
    debug "stack after run ", calc.stack
    i += 1
    var deleted = true
    while deleted:
      deleted = false
      for cmd in calc.tmpCommands.keys:
        deleted = calc.cleanTmp(cmd)
  result = calc.messages
  calc.messages = ""

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
      discard calc.cleanTmp command
      calc.messages &= calc.execute cmd
    else:
      calc.pushValue(command)
  if verbose:
    calc.messages &= $calc.stack & " <- " & command & "\n"
