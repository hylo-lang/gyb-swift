import Testing

@testable import gyb_swift

// MARK: - Test Helpers

/// Executes `text` as a template and returns the output.
func execute(
    _ text: String,
    bindings: [String: Any] = [:],
    filename: String = "test",
    lineDirective: String = ""
) throws -> String {
    let ast = try parseTemplate(filename: filename, text: text)
    let generator = CodeGenerator(
        templateText: text,
        filename: filename,
        lineDirective: lineDirective,
        emitSourceLocation: true
    )
    return try generator.execute(ast, bindings: bindings)
}

/// Generates Swift code for `text` as a template with `bindings`.
func generateCode(
    _ text: String,
    bindings: [String: Any] = [:],
    filename: String = "test.gyb",
    lineDirective: String = "//# line \\(line) \"\\(file)\"",
    emitSourceLocation: Bool = true
) throws -> String {
    let ast = try parseTemplate(filename: filename, text: text)
    let generator = CodeGenerator(
        templateText: text,
        filename: filename,
        lineDirective: lineDirective,
        emitSourceLocation: emitSourceLocation
    )
    return generator.generateCompleteProgram(ast, bindings: bindings)
}

/// Helper to create a token with String text for testing
func token(_ kind: TemplateToken.Kind, _ text: String) -> TemplateToken {
    TemplateToken(kind: kind, text: text[...])
}
