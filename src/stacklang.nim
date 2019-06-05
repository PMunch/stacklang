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
  Print = "print"; "Prints the element on top off the stack without poping it":
    echo stack[^1]
  StackSwap = "swap"; "Swaps the two bottom elements on the stack":
    let
      a = stack[^1]
      b = stack[^2]
    stack[^1] = b
    stack[^2] = a
  StackRotate = "rot"; "Rotates the stack one level":
    stack.insert(stack.pop, 0)
  Until = "until"; "Takes a label and a command and runs the command until the topmost element on the stack is the label":
    let
      lbl = stack[^2]
      cmd = stack[^1].strVal
    stack.setLen(stack.len - 2)
    case lbl.kind:
    of Float:
      if lbl.floatVal.int >= 0:
        while stack.len != lbl.floatVal.int + 1:
          runCmd(cmd, false)
      else:
        let prelen = stack.len
        while stack.len != prelen + lbl.floatVal.int + 1:
          runCmd(cmd, false)
    of String:
      while stack[^2].kind != String or stack[^2].strVal != lbl.strVal:
        runCmd(cmd, false)
  MakeCommand = "mkcmd"; "Start defining a new command":
    mkcmd = true
    echo cmdstack
    verbose = false
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

# Program main loop, read input from stdin, run our template to parse the
# command and run the corresponding operation. if that fails try to push it as
# a number. Print out our "stack" for every iteration of the loop

proc runCmd(command: string, verbose = true) =
  var verbose = verbose
  block runblock:
    try:
      runCommand(command)
      break runblock
    except:
      discard

    if customCommands.hasKey(command):
      let cc = customCommands[command]
      var i = cc.low
      while i <= cc.high:
        echo "dbg: ", cc[i], " ", stack
        case cc[i]:
        of "goto":
          # goto means read the label of the stack and go backwards through the
          # command list until it's found
          let destination = stack.pop
          case destination.kind:
          of String:
            let label = destination.strVal
            i -= 2
            while cc[i] != label:
              i -= 1
          of Float:
            let pos = destination.floatVal.int
            if pos >= 0:
              i = pos
            else:
              i -= pos
        of "<":
          let
            a = stack[^2]
            b = stack[^1]
          stack.setLen(stack.len - 2)
          if a.kind != b.kind:
            echo "Can't compare ", a, " to ", b, " since they are of different types"
          else:
            case a.kind:
            of Float:
              if a.floatVal < b.floatVal: i += 1 else: i += 2
            of String:
              if a.strVal < b.strVal: i += 1 else: i += 2
        else: discard
        runCmd(cc[i], false)
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
  for command in stdin.readLine.split(" "):
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
          echo stack
          cmdstack = @[]
          mkcmd = false
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
      echo cmdstack
