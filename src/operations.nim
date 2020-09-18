import macros except body
import macroutils

template assureKind(expectedKind: ElementKind or set[ElementKind], element: untyped): Element =
  let value = element
  if (when expectedKind is ElementKind: value.kind != expectedKind else: value.kind notin expectedKind):
    var e = newException(ArgumentError, "Wrong type passed to command, expected " & $expectedKind & ", but got " & $value.kind)
    e.currentCommand = calc.awaitingCommands[^1]
    raise e
  value

macro defineCommands*(enumName, docarrayName, runnerName,
  definitions: untyped): untyped =
  let calc = newIdentNode("calc")
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
    cmd = newIdentNode("result")
  for i in countup(0, definitions.len - 1, 2):
    let
      enumInfo = definitions[i]
      commandInfo = definitions[i+1]
    let command = superQuote do:
      `cmd` = some(iterator () {.closure.} =
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
        if kind.kind == nnkInfix:
          var
            kinds = nnkCurly.newTree
            documentations = nnkCurly.newTree
          proc findKinds(x: NimNode) =
            case x.kind:
            of nnkIdent:
              case parseEnum[Argument]($x):
              of ANumber:
                kinds.add newIdentNode("Number")
                documentations.add newIdentNode("ANumber")
              of AString:
                kinds.add newIdentNode("String")
                documentations.add newIdentNode("AString")
              of ALabel:
                kinds.add newIdentNode("Label")
                documentations.add newIdentNode("ALabel")
              of AAny: assert false
            of nnkInfix:
              assert $x[0] in ["|", "or"]
              findKinds(x[1])
              findKinds(x[2])
            else: assert false
          kind.findKinds()
          command[1][1].body.insert(0, quote do:
            let `letterIdent` = assureKind(`kinds`, `calc`.pop())
          )
          documentation[^1][1][1].add documentations
        else:
          command[1][1].body.insert(0, case parseEnum[Argument]($kind):
            of ANumber: (quote do:
              let n = assureKind(Number, `calc`.pop())
              let `letterIdent` = n.num
              let `letterIdentEnc` = n.encoding)
            of AString: (quote do:
              let `letterIdent` = assureKind(String, `calc`.pop()).str)
            of ALabel: (quote do:
              let `letterIdent` = assureKind(Label, `calc`.pop()).lbl)
            of AAny: (quote do:
              let `letterIdent` = `calc`.pop()))
          documentation[^1][1][1].add nnkCurly.newTree(case $kind:
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
    proc `runnerName`*(`calc`: Calc, `templateArgument`: string): Option[iterator() {.closure.}] =
      #var `cmd`: Option[iterator() {.closure.}]
      #block runnerBody:
      var `parsedEnum`: `enumName`
      try:
        `parsedEnum` = `parseStmt`
      except:
        return
      `caseSwitch`
      #`cmd`
  when defined(echoOperations):
    echo result.repr
