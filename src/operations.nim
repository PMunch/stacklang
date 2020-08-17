import macros except body
import macroutils

template assureKind(expectedKind: ElementKind, element: untyped): Element =
  let value = element
  if value.kind != expectedKind:
    var e = newException(ArgumentError, "Wrong type passed to command, expected " & $expectedKind & ", but got " & $value.kind)
    e.currentCommand = calc.awaitingCommands[^1]
    raise e
  value

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
          newIdentNode("Documentation")
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
    let documentation = superQuote do:
      Documentation(msg: `commandInfo[0]`, arguments: @[])
    if enumInfo[1].kind == nnkStrLit:
      enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1])
    else:
      enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1][^1])
      var letter = 'a'
      for kind in enumInfo[1][0..^2]:
        let letterIdent = newIdentNode($letter)
        let letterIdentEnc = newIdentNode($letter & "_encoding")
        command[1][0].body.insert(0, case $kind:
          of "n": (quote do:
            let n = assureKind(Number, calc.pop())
            let `letterIdent` = n.num
            let `letterIdentEnc` = n.encoding)
          of "s": (quote do:
            let `letterIdent` = calc.pop().str)
          of "l": (quote do:
            let `letterIdent` = calc.pop().lbl)
          of "a": (quote do:
            let `letterIdent` = calc.pop())
          else: (quote do:
            assert false))
        documentation[^1][1][1].add(case $kind:
          of "n": newIdentNode("ANumber")
          of "s": newIdentNode("AString")
          of "l": newIdentNode("ALabel")
          of "a": newIdentNode("AAny")
          else: nnkDiscardStmt.newTree)
        letter = chr(letter.ord + 1)
    docstrings[0][2].add documentation #commandInfo[0]
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
        `caseSwitch`
      `cmd`
  when defined(echoOperations):

    echo result.repr
