import math, strutils, tables, os
import operations

# First create a simple "stack" implementation
type
  ElementKind = enum String, Float
  Element = object
    case kind: ElementKind
    of String:
      strVal: string
    of Float:
      floatVal: float
  #Stack[T] {.borrow: [pop, `[]`, len, setLen].} = distinct seq[T]
  Stack[T] = seq[T]

proc `$`(element: Element): string =
  case element.kind:
  of Float: $element.floatVal
  of String: $element.strVal

var
  stack: Stack[Element]
  cmdstack: seq[string]
  mkcmd = false
  customCommands = initTable[string, seq[string]]()
  variables = initTable[string, Element]()

template push[T](stack: var Stack[T], value: T) =
  seq[T](stack).add value

proc `$`[T](stack: Stack[T]): string =
  result = "["
  for elem in stack:
    result &= $elem & "  "
  result.setLen(max(result.len - 1, 2))
  result[^1] = ']'

# Convenience template to execute an operation over two operands from the stack
template execute[T](stack: var Stack[T], operation: untyped): untyped {.dirty.} =
  if stack[^1].kind != Float:
    echo "Expected two floats but x is not a float: ", stack[^1]
  elif stack[^2].kind != Float:
    echo "Expected two floats but y is not a float: ", stack[^2]
  else:
    let
      a = stack[^1].floatVal
      b = stack[^2].floatVal
    stack.setLen(stack.len - 2)
    stack.push(Element(kind: Float, floatVal: operation))

template simpleExecute[T](stack: var seq[T], operation: untyped): untyped {.dirty.} =
  if stack[^1].kind != Float:
    echo "Expected a float but x is not a float: ", stack[^1]
  else:
    let a = stack.pop.floatVal
    stack.push(Element(kind: Float, floatVal: operation))

# Then define all our commands using our macro
defineCommands(Commands, docstrings, runCommand):
  Plus = "+"; "Adds two numbers":
    stack.execute(a + b)
  Minus = "-"; "Subtract two numbers":
    stack.execute(b - a)
  Multiply = "*"; "Multiplies two numbers":
    stack.execute(a * b)
  Divide = "/"; "Divides two numbers":
    stack.execute(b / a)
  Sqrt = "sqrt"; "Takes the square root of a number":
    stack.simpleExecute(sqrt(a))
  Power = "^"; "Takes one number and raises it to the power of another":
    stack.execute(b.pow(a))
  Sine = "sin"; "Takes the sine of a number":
    stack.simpleExecute(sin(a))
  Cosine = "cos"; "Takes the cosine of a number":
    stack.simpleExecute(cos(a))
  Tangent = "tan"; "Takes the tangent of a number":
    stack.simpleExecute(tan(a))
  DegToRad = "dtr"; "Converts a number from degrees to radians":
    stack.simpleExecute(degToRad(a))
  RadToDeg = "rtd"; "Converts a number from radians to degrees":
    stack.simpleExecute(radToDeg(a))
  Modulo = "mod"; "Takes the modulo of one number over another":
    stack.execute(b mod a)
  Pop = "pop"; "Pops an element off the stack and discards it":
    discard stack.pop
  Display = "display"; "Shows the element on top off the stack without poping it":
    echo stack[^1]
  Print = "print"; "Takes a number of things, then prints those things in FIFO order with space separators":
    if stack[^1].kind != Float:
      echo "Must be passed a count"
    else:
      let count = stack.pop.floatVal.int
      for i in stack.high-count+1..stack.high:
        stdout.write $stack[i] & " "
      echo ""
      stack.setLen(stack.len - count)
  StackSwap = "swap"; "Swaps the two bottom elements on the stack":
    let
      a = stack[^1]
      b = stack[^2]
    stack[^1] = b
    stack[^2] = a
  StackRotate = "rot"; "Rotates the stack one level":
    stack.insert(stack.pop, 0)
  StackInsert = "insert"; "Takes an element and a number and inserts the element at that position in the stack":
    let
      el = stack[^2]
      pos = stack[^1].floatVal.int
    stack.setLen(stack.len - 2)
    if pos >= 0:
      stack.insert(el, pos)
    else:
      stack.insert(el, stack.len + pos)
  Delete = "del"; "Deletes the element of the stack at a given position":
    let pos = stack.pop.floatVal.int
    if pos >= 0:
      stack.delete(pos)
    else:
      stack.delete(stack.high + pos)
  Until = "until"; "Takes a label and a command and runs the command until the topmost element on the stack is the label":
    let
      lbl = stack[^2]
      cmd = stack[^1].strVal
    stack.setLen(stack.len - 2)
    case lbl.kind:
    of Float:
      if lbl.floatVal.int >= 0:
        var runLast = false
        while stack.len != lbl.floatVal.int and not runLast:
          if stack.len == lbl.floatVal.int + 1:
            runLast = true
          runCmd(cmd)
      else:
        let prelen = stack.len
        var runLast = false
        while stack.len != prelen + lbl.floatVal.int and not runLast:
          if stack.len == lbl.floatVal.int + 1:
            runLast = true
          runCmd(cmd)
    of String:
      while stack[^2].kind != String or stack[^2].strVal != lbl.strVal:
        runCmd(cmd)
  Store = "store"; "Takes an element and a label and stores the element as a variable that can later be retrieved by load":
    if stack[^1].kind != String:
      echo "Last element on stack must be a label"
    else:
      variables[stack[^1].strVal] = stack[^2]
      stack.setLen(stack.len - 2)
  Load = "load"; "Takes a label and loads the variable by that name back onto the stack, removing the variable":
    if stack[^1].kind != String:
      echo "Last element on stack must be a label"
    else:
      if not variables.take(stack[^1].strVal, stack[^1]):
        echo "No variable named ", stack[^1]
  Dup = "dup"; "Duplicates the last element on the stack":
    stack.push stack[^1]
  Nop = "nop"; "Does nothing":
    discard
  MakeCommand = "mkcmd"; "Start defining a new command":
    mkcmd = true
  DeleteCommand = "delcmd"; "Deletes the command given by the last label":
    let cmdName = stack.pop.strVal
    if customCommands.hasKey cmdName:
      customCommands.del cmdName
    else:
      echo "No custom command with name ", cmdName, " found"
  ListCommands = "lscmd"; "Lists all the custom commands":
    echo "These are the currently defined custom commands"
    for name, command in customCommands.pairs:
      echo name, "\t", command
    echo stack
    verbose = false
  Help = "help"; "Lists all the commands with documentation":
    echo "Commands:"
    for command in Commands:
      echo "\t", command, "\t", docstrings[command]
  Exit = "exit"; "Exits the program, saving custom commands":
    var output = open("stacklang.custom", fmWrite)
    for name, command in customCommands.pairs:
      output.writeLine(command.join(" ") & " " & name)
    output.close()
    quit 0

template compare[T](stack: var Stack[T], operation: untyped): untyped {.dirty.} =
  let
    a = stack[^2]
    b = stack[^1]
  stack.setLen(stack.len - 2)
  if a.kind != b.kind:
    echo "Can't compare ", a, " to ", b, " since they are of different types"
  else:
    let condition =
      if a.kind == Float:
        operation(a.floatVal, b.floatVal)
      else:
        operation(a.strVal, b.strVal)
    if operation(a.floatVal, b.floatVal):
      i += 1
      let oldi = i
      runCmdCmd(cc, i, labelGotos)
      if i == oldi:
        i += 1
    else:
      i += 2
      runCmdCmd(cc, i, labelGotos)

# Program main loop, read input from stdin, run our template to parse the
# command and run the corresponding operation. if that fails try to push it as
# a number. Print out our "stack" for every iteration of the loop

proc runCmd(command: string, verbose = false)

proc runCmdCmd(cc: seq[string], i: var int, labelGotos: var CountTable[string]) =
  case cc[i]:
  of "goto":
    try:
      let destination = stack.pop
      case destination.kind:
      of String:
        let label = destination.strVal
        labelGotos.inc(label)
        i = cc.find(label)
      of Float:
        let pos = destination.floatVal.int
        if pos >= 0:
          i = pos
        else:
          i -= pos
      runCmdCmd(cc, i, labelGotos)
    except:
      echo getCurrentExceptionMsg()
      raise
  of "<":
    stack.compare(`<`)
  of ">":
    stack.compare(`>`)
  of "=":
    stack.compare(`==`)
  of "!=":
    stack.compare(`!=`)
  of "<=":
    stack.compare(`<=`)
  of ">=":
    stack.compare(`>=`)
  of "lblcnt":
    stack.push Element(kind: Float, floatVal: labelGotos.getOrDefault(stack.pop().strVal, 0).float)
    i += 1
    runCmdCmd(cc, i, labelGotos)
  else:
    runCmd(cc[i], true)

proc runCmd(command: string, verbose = false) =
  var verbose = verbose
  block runblock:
    try:
      runCommand(command)
      break runblock
    except: discard

    if customCommands.hasKey(command):
      let cc = customCommands[command]
      var
        labelGotos = initCountTable[string]()
        i = cc.low
      while i <= cc.high:
        runCmdCmd(cc, i, labelGotos)
        i += 1
    else:
      try:
        stack.push Element(kind: Float, floatVal: parseFloat(command))
      except:
        if command[0] == '\\':
          stack.push Element(kind: String, strVal: command[1..^1])
        else:
          stack.push Element(kind: String, strVal: command)
        break runblock
  if verbose:
    echo stack, " <- ", command

echo "Welcome to stacklang!"
echo "This is a very simple stack based calculator/language that is a"
echo "spiritual succesor to the greatness of the HP-41C. To add numbers or run"
echo "commands simply type them here. You can also separate multiple numbers"
echo "and commands by a space. You can also add text labels, and to add a"
echo "label that has already been assigned to a custom command you can prefix"
echo "it with a backslash. To see more of what you can do simply type 'help'"
if fileExists("stacklang.custom"):
  for line in "stacklang.custom".lines:
    let words = line.split(" ")
    customCommands[words[^1]] = words[0..^2]
  echo "Custom commands loaded from stacklang.custom, to see them use lscmd"
else:
  echo "No custom commands file found"

echo stack
while true:
  let
    commands = stdin.readLine
    wasmkcmd = mkcmd
  var madecmd = false
  for command in commands.split(" "):
    if not mkcmd:
      runCmd(command)
    else:
      case command:
      of "undo":
        cmdstack.setLen(cmdstack.len - 1)
      of "fin":
        let name = cmdstack.pop
        var valid = true
        try:
          discard parseEnum[Commands](name)
          echo "Command name can't be one of the built-in commands"
          valid = false
        except: discard
        try:
          discard parseFloat(name)
          echo "Command name can't be a valid float number"
          valid = false
        except: discard
        if valid:
          customCommands[name] = cmdstack
          echo name, " -> ", cmdstack
          cmdstack = @[]
          mkcmd = false
          madecmd = true
          continue
        else:
          cmdstack.push name
      of "pause":
        mkcmd = false
      of "exit":
        mkcmd = false
        cmdstack = @[]
      of "help":
        echo "You are in command making mode"
        echo "\tundo\tremoves the last entry from the command"
        echo "\tfin\tfinalizes the command. The last entry on the stack"
        echo "\t\tmust be a label and will be used as the command name"
        echo "\thelp\tshows this help message"
        echo "\texit\texits the command making mode without making a command"
        echo "\tpause\texits the command making mode but stores the current"
        echo "\t\tcommand stack until you come back to command create mode"
        echo "All other commands and numbers will be added to the command"
      else:
        cmdstack.add command
  if (wasmkcmd or mkcmd) and not madecmd:
    echo "c", cmdstack, " <- ", commands
  else:
    echo stack, " <- ", commands
