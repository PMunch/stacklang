import math, strutils

type
  ElementKind* = enum String, Label, Number
  Element* = object
    case kind*: ElementKind
    of Label:
      lbl*: string
    of String:
      str*: string
    of Number:
      num*: float
  Stack*[T] = seq[T]

template push*[T](stack: var Stack[T], value: T) =
  stack.add value

template pop*[T](stack: var Stack[T]): T =
  block:
    if stack.len == 0:
      yield
    command.elems.add stack[^1]
    stack.setLen stack.len - 1
    command.elems[^1]

proc pushNumber*(stack: var Stack[Element], x: float) =
  stack.push Element(kind: Number, num: x)

proc pushString*(stack: var Stack[Element], x: string) =
  stack.push Element(kind: String, str: x)

proc pushLabel*(stack: var Stack[Element], x: string) =
  assert not x.contains ' ', "Label cannot contain spaces"
  stack.push Element(kind: Label, lbl: x)

proc pushValue*(stack: var Stack[Element], value: string) =
  case value:
  of "pi":
    stack.push Element(kind: Number, num: Pi)
  of "tau":
    stack.push Element(kind: Number, num: Tau)
  of "e":
    stack.push Element(kind: Number, num: E)
  else:
    try:
      stack.push Element(kind: Number, num: parseFloat(value))
    except:
      if value[0] == '\\':
        assert not value.contains ' ', "Label cannot contain spaces"
        stack.push Element(kind: Label, lbl: value[1..^1])
      elif value[0] == '"':
        stack.push Element(kind: String, str: value[1..^2])
      else:
        assert not value.contains ' ', "Label cannot contain spaces"
        stack.push Element(kind: Label, lbl: value)
