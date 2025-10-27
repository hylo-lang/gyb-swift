import Testing

@testable import gyb_swift

@Test("parse simple literal template")
func parse_literalTemplate() throws {
  let text = "Hello, World!"
  let ast = try parseTemplate(filename: "test", text: text)

  #expect(ast.count == 1)
  #expect(ast[0] is LiteralNode)
}

@Test("parse template with escaped symbols")
func parse_templateWithEscapedSymbols() throws {
  let text = "$$dollar and %%percent"
  let ast = try parseTemplate(filename: "test", text: text)

  #expect(ast.count >= 1)
}

@Test("parse substitution")
func parse_substitution() throws {
  let text = "${x}"
  let ast = try parseTemplate(filename: "test", text: text)

  #expect(ast.count == 1)
  #expect(ast[0] is SubstitutionNode)
}

@Test("parse code block")
func parse_codeBlock() throws {
  let text = "%{ let x = 42 }%"
  let ast = try parseTemplate(filename: "test", text: text)

  #expect(ast.count == 1)
  #expect(ast[0] is CodeNode)
}

@Test("AST structure for mixed template")
func ast_structure() throws {
  let text = "Text ${x} more text"
  let ast = try parseTemplate(filename: "test", text: text)

  #expect(ast.count >= 1)

  var hasSubstitution = false
  for child in ast {
    if child is SubstitutionNode {
      hasSubstitution = true
    }
  }
  #expect(hasSubstitution)
}

@Test("AST node creation")
func astNode_creation() {
  let literal = LiteralNode(text: "hello")
  #expect(literal.text == "hello")

  let code = CodeNode(code: "let x = 1", sourcePosition: "".startIndex)
  #expect(code.code == "let x = 1")

  let subst = SubstitutionNode(expression: "x")
  #expect(subst.expression == "x")

  let ast: AST = [literal]
  #expect(ast.count == 1)
}

@Test("all major components can be instantiated")
func components_instantiation() {
  // Test tokenizer - verify it can be created and used
  var tokenizer = TemplateTokens(text: "test")
  _ = tokenizer.next()  // Verify it works

  // Test parse context
  let context = ParseContext(filename: "test", text: "content")
  #expect(context.filename == "test")
}
