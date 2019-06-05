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

proc `$`(element: Element): string =
  case element.kind:
  of Float: $element.floatVal
  of String: $element.strVal

var
  stack: seq[Element]
  cmdstack: seq[string]
  mkcmd = false
  customCommands = initTable[string, seq[string]]()

template push[T](stack: var seq[T], value: T) =
  stack.add value

# Convenience template to execute an operation over two operands from the stack
template execute[T](stack: var seq[T], operation: untyped): untyped {.dirty.} =
  let
    a = stack[^1].floatVal
    b = stack[^2].floatVal
  stack.setLen(stack.len - 2)
  stack.push(Element(kind: Float, floatVal: operation))

template simpleExecute[T](stack: var seq[T], operation: untyped): untyped {.dirty.} =
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
  Print = "print"; "Pops an element off the stack and prints it":
    echo stack.pop
  StackSwap = "swap"; "Swaps the two bottom elements on the stack":
    let
      a = stack[^1]
      b = stack[^2]
    stack[^1] = b
    stack[^2] = a
  StackRotate = "rot"; "Rotates the stack one level":
    stack.insert(stack.pop, 0)
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
      for cmd in customCommands[command]:
        runCmd(cmd, false)
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
