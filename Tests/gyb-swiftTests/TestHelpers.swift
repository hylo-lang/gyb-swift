import Testing

@testable import gyb_swift

// MARK: - Test Helpers

/// Executes `text` as a template and returns the output.
func execute(
  _ text: String,
  bindings: [String: String] = [:],
  filename: String = "test"
) throws -> String {
  let ast = try AST(filename: filename, text: text)
  let generator = CodeGenerator(
    templateText: text,
    filename: filename
  )
  return try generator.execute(ast, bindings: bindings)
}

/// Generates Swift code for `text` as a template with `bindings`.
func generateCode(
  _ text: String,
  bindings: [String: String] = [:],
  filename: String = "test.gyb",
  lineDirective: String = "",
  emitLineDirectives: Bool = false
) throws -> String {
  let ast = try AST(filename: filename, text: text)
  let generator = CodeGenerator(
    templateText: text,
    filename: filename,
    lineDirective: lineDirective,
    emitLineDirectives: emitLineDirectives
  )
  return generator.generateCompleteProgram(ast, bindings: bindings)
}

/// Helper to create a token with String text for testing
func token(_ kind: TemplateToken.Kind, _ text: String) -> TemplateToken {
  TemplateToken(kind: kind, text: text[...])
}
