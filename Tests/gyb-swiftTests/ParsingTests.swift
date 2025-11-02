import Testing

@testable import gyb_swift

@Test("parse simple literal template")
func parse_literalTemplate() throws {
  let ast = try AST(filename: "test", text: "Hello, World!")
  #expect(ast.count == 1)
  #expect(ast[0] is LiteralNode)
}

@Test("parse template with escaped symbols")
func parse_templateWithEscapedSymbols() throws {
  #expect(try AST(filename: "test", text: "$$dollar and %%percent").count >= 1)
}

@Test("parse substitution")
func parse_substitution() throws {
  let ast = try AST(filename: "test", text: "${x}")
  #expect(ast.count == 1)
  #expect(ast[0] is SubstitutionNode)
}

@Test("parse code block")
func parse_codeBlock() throws {
  let ast = try AST(filename: "test", text: "%{ let x = 42 }%")
  #expect(ast.count == 1)
  #expect(ast[0] is CodeNode)
}

@Test("AST structure for mixed template")
func ast_structure() throws {
  let ast = try AST(filename: "test", text: "Text ${x} more text")
  #expect(ast.count >= 1)
  #expect(ast.contains { $0 is SubstitutionNode })
}

@Test("AST node creation")
func astNode_creation() {
  #expect(LiteralNode(text: "hello").text == "hello")
  #expect(CodeNode(code: "let x = 1", sourcePosition: "".startIndex).code == "let x = 1")
  #expect(SubstitutionNode(expression: "x").expression == "x")
  #expect(AST([LiteralNode(text: "hello")]).count == 1)
}

@Test("all major components can be instantiated")
func components_instantiation() {
  var tokenizer = TemplateTokens(text: "test")
  _ = tokenizer.next()
  #expect(Parser(filename: "test", text: "content").filename == "test")
}
