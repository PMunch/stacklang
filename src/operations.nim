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
    # TODO: Rewrite as a let block with variable names a, b, c, etc.
    var variables = nnkPar.newTree()
    if enumInfo[1].kind == nnkStrLit:
      enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1])
    else:
      enumDef[0][2].add nnkEnumFieldDef.newtree(enumInfo[0], enumInfo[1][^1])
      for i, kind in enumInfo[1][0..^2]:
        variables.insert(0, nnkBracketExpr.newTree(
          newDotExpr(newIdentNode("calc"), newIdentNode("stack")),
          nnkPrefix.newTree(newIdentNode("^"), newLit(i + 1))
        ))
        # TODO: add case for Position (positive, negative, label)
        case kind.strVal:
        of "a":
          signatures[0][2][0][1][1].add newIdentNode("Any")
        of "l":
          # TODO: Clean up these blocks..
          signatures[0][2][0][1][1].add newIdentNode("Label")
          variables[0] = newStmtList(nnkIfStmt.newTree(
            nnkElifBranch.newTree(nnkInfix.newTree(newIdentNode("=="),
              newDotExpr(variables[0], newIdentNode("kind")),
              newIdentNode("String")),
            newDotExpr(variables[0], newIdentNode("floatVal"))),
            nnkElse.newTree(nnkRaiseStmt.newTree(newCall(newIdentNode("newException"),
              newIdentNode("ValueError"),
              nnkInfix.newTree(newIdentNode("&"),
                nnkInfix.newTree(newIdentNode("&"),
                  newLit("Expected a string at position -" & $(i+1) & " but "),
                  nnkPrefix.newTree(newIdentNode("$"), variables[0])),
                newLit(" is not a string")))))))
        of "n":
          signatures[0][2][0][1][1].add newIdentNode("Number")
          variables[0] = newStmtList(nnkIfStmt.newTree(
            nnkElifBranch.newTree(nnkInfix.newTree(newIdentNode("=="),
              newDotExpr(variables[0], newIdentNode("kind")),
              newIdentNode("Float")),
            newDotExpr(variables[0], newIdentNode("floatVal"))),
            nnkElse.newTree(nnkRaiseStmt.newTree(newCall(newIdentNode("newException"),
              newIdentNode("ValueError"),
              nnkInfix.newTree(newIdentNode("&"),
                nnkInfix.newTree(newIdentNode("&"),
                  newLit("Expected a float at position -" & $(i+1) & " but "),
                  nnkPrefix.newTree(newIdentNode("$"), variables[0])),
                newLit(" is not a float")))))))
        else: discard
    docstrings[0][2].add commandInfo[0]
    let varLen = newLit(variables.len)
    caseSwitch.add nnkOfBranch.newTree(
      enumInfo[0],
      newStmtList(
        if variables.len > 0: newLetStmt(newIdentNode("vars"), variables) else: nnkDiscardStmt.newTree(newLit(0)),
        if variables.len > 0: (quote do:
          calc.stack.setLen(calc.stack.len - `varLen`)
        ) else: nnkDiscardStmt.newTree(newLit(0)),
        commandInfo[1]
      )
    )
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
