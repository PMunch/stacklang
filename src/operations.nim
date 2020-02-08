import macros, sequtils, strutils

type
  StackError* = object of IndexError
    currentCommand*: string
  Type* = enum Number, Label, Any

macro defineCommands*(enumName, docarrayName, signaturesName, runnerName,
  definitions: untyped): untyped =
  var
    enumDef = nnkTypeSection.newTree(
      nnkTypeDef.newTree(
        nnkPostfix.newTree(
          newIdentNode "*",
          enumName
        ),
        newEmptyNode(),
        nnkEnumTy.newTree(newEmptyNode())))
    docstrings =  nnkConstSection.newTree(
      nnkConstDef.newTree(
        nnkPostfix.newTree(
          newIdentNode "*",
          docarrayName
        ),
        nnkBracketExpr.newTree(
          newIdentNode("array"),
          enumName,
          newIdentNode("string")
        ),
        nnkBracket.newTree()))
    signatures =  nnkConstSection.newTree(
      nnkConstDef.newTree(
        nnkPostfix.newTree(
          newIdentNode "*",
          signaturesName
        ),
        nnkBracketExpr.newTree(
          newIdentNode("array"),
          enumName,
          nnkBracketExpr.newTree(
            newIdentNode("seq"),
            newIdentNode("Type")
          )
        ),
        nnkBracket.newTree()))
    templateArgument = newIdentNode("command")
    parseStmt = nnkCall.newTree(
      nnkBracketExpr.newTree(
        newIdentNode("parseEnum"),
        enumName
      ),
      templateArgument)
    parsedEnum = newIdentNode("parsedEnum")
    caseSwitch =  nnkCaseStmt.newTree(parsedEnum)
  for i in countup(0, definitions.len - 1, 2):
    let
      enumInfo = definitions[i]
      commandInfo = definitions[i+1]
    signatures[0][2].add nnkCall.newTree(
      nnkBracketExpr.newTree(
        newIdentNode("seq"),
        newIdentNode("Type")
      ),
      nnkPrefix.newTree(
        newIdentNode("@"),
        nnkBracket.newTree()
      )
    )
    if enumInfo[1].kind == nnkStrLit:
      enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1])
    else:
      enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1][^1])
      for kind in enumInfo[1][0..^2]:
        case kind.strVal:
        of "a": signatures[0][2][0][1][1].add newIdentNode("Any")
        of "l": signatures[0][2][0][1][1].add newIdentNode("Label")
        of "n": signatures[0][2][0][1][1].add newIdentNode("Number")
        else: discard
    docstrings[0][2].add commandInfo[0]
    caseSwitch.add nnkOfBranch.newTree(
      enumInfo[0],
      commandInfo[1])
  result = quote do:
    `enumDef`
    `docstrings`
    `signatures`
    template `runnerName`(`templateArgument`: untyped, parseFail: untyped): untyped =
      block runnerBody:
        var `parsedEnum`: `enumName`
        try:
          `parsedEnum` = `parseStmt`
        except:
          parseFail
          break runnerBody
        try:
          `caseSwitch`
        except IndexError as e:
          var se = newException(StackError, "IndexError while running command", e)
          se.currentCommand = `templateArgument`
          raise se
  when defined(echoOperations):

    echo result.repr
