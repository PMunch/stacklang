import macros except body
import macroutils

type
  StackError* = object of IndexError
    currentCommand*: string

macro defineCommands*(enumName, docarrayName, runnerName,
  definitions: untyped): untyped =
  echo definitions.treeRepr
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
    cmd = newIdentNode("cmd")
  for i in countup(0, definitions.len - 1, 2):
    let
      enumInfo = definitions[i]
      commandInfo = definitions[i+1]
    let command = superQuote do:
      `cmd` = (iterator () {.closure.} =
        `commandInfo[1]`
      )
    echo command.treeRepr
    if enumInfo[1].kind == nnkStrLit:
      enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1])
    else:
      enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1][^1])
      var letter = 'a'
      for kind in enumInfo[1][0..^2]:
        let letterIdent = newIdentNode($letter)
        command[1][0].body.insert(0, case $kind:
          of "n": (quote do:
            let `letterIdent` = calc.pop().num)
          of "s": (quote do:
            let `letterIdent` = calc.pop().str)
          of "l": (quote do:
            let `letterIdent` = calc.pop().lbl)
          of "a": (quote do:
            let `letterIdent` = calc.pop())
          else: (quote do:
            assert false))
        letter = chr(letter.ord + 1)
    docstrings[0][2].add commandInfo[0]
    caseSwitch.add nnkOfBranch.newTree(
      enumInfo[0],
      command)
  result = quote do:
    `enumDef`
    `docstrings`
    template `runnerName`(`templateArgument`: untyped, parseFail: untyped): untyped {.dirty.} =
      var `cmd`: iterator() {.closure.}
      block runnerBody:
        var `parsedEnum`: `enumName`
        try:
          `parsedEnum` = `parseStmt`
        except:
          `cmd` = (iterator () {.closure.} =
            parseFail
          )
          break runnerBody
        try:
          `caseSwitch`
        except IndexError as e:
          var se = newException(StackError, "IndexError while running command", e)
          se.currentCommand = `templateArgument`
          raise se
      `cmd`
  when defined(echoOperations):

    echo result.repr
