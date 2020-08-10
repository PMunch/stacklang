import macros

type
  StackError* = object of IndexError
    currentCommand*: string

macro defineCommands*(enumName, docarrayName, runnerName,
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
    enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1])
    docstrings[0][2].add commandInfo[0]
    caseSwitch.add nnkOfBranch.newTree(
      enumInfo[0],
      commandInfo[1])
  result = quote do:
    `enumDef`
    `docstrings`
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
