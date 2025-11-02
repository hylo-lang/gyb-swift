import Testing

@testable import gyb_swift

// MARK: - Test Helpers

/// Executes `template` and returns the output.
func execute(
  _ template: String,
  bindings: [String: String] = [:],
  filename: String = "test"
) throws -> String {
  let ast = try AST(filename: filename, template: template)
  let generator = CodeGenerator(
    template: template,
    filename: filename
  )
  let swiftCode = generator.generateCompleteProgram(ast, bindings: bindings)
  let runner = SwiftScriptRunner(filename: filename)
  return try runner.execute(swiftCode)
}

/// Generates Swift code for `template` with `bindings`.
func generateCode(
  _ template: String,
  bindings: [String: String] = [:],
  filename: String = "test.gyb",
  lineDirective: String = "",
  emitLineDirectives: Bool = false
) throws -> String {
  let ast = try AST(filename: filename, template: template)
  let generator = CodeGenerator(
    template: template,
    filename: filename,
    lineDirective: lineDirective,
    emitLineDirectives: emitLineDirectives
  )
  return generator.generateCompleteProgram(ast, bindings: bindings)
}

/// Helper to create a token with String content for testing
func token(_ kind: TemplateToken.Kind, _ content: String) -> TemplateToken {
  TemplateToken(kind: kind, text: content[...])
}
