import Foundation
import RegexBuilder
import Testing

@testable import gyb_swift

@Test("compilation error includes filename and compiler output")
func error_compilationFailure() throws {
  // Template with invalid Swift code
  let text = """
    % let x: InvalidType = 42
    ${x}
    """

  let error = #expect(throws: (any Error).self) {
    try execute(text, filename: "test.gyb")
  }

  guard let gybError = error as? GYBError else {
    Issue.record("Expected GYBError, got \(type(of: error))")
    return
  }

  let description = gybError.description
  // Should include filename
  #expect(description.contains("test.gyb"))
  // Should include "executing" to indicate the error phase
  #expect(description.contains("executing"))
  // Should include error output (with newline separator)
  #expect(description.contains("\n"))
  // Error should mention the invalid type
  #expect(description.contains("InvalidType") || description.contains("cannot find"))
}

@Test("execution error includes filename and error output")
func error_executionFailure() throws {
  // Template that compiles but crashes at runtime
  let text = """
    % fatalError("test crash")
    """

  let error = #expect(throws: (any Error).self) {
    try execute(text, filename: "crash.gyb")
  }

  guard let gybError = error as? GYBError else {
    Issue.record("Expected GYBError, got \(type(of: error))")
    return
  }

  let description = gybError.description
  // Should include filename
  #expect(description.contains("crash.gyb"))
  // Should include "executing" to indicate execution phase
  #expect(description.contains("executing"))
  // Should include error output (with newline separator)
  #expect(description.contains("\n"))
  // Should mention the fatal error or crash
  #expect(
    description.contains("Fatal error") || description.contains("test crash")
      || description.contains("Illegal"))
}

@Test("error messages start compiler output on new line for IDE parsing")
func error_messageFormat() throws {
  let text = "% let x: BadType = 1"

  let error = #expect(throws: (any Error).self) {
    try execute(text, filename: "test.gyb")
  }

  guard let gybError = error as? GYBError else {
    Issue.record("Expected GYBError, got \(type(of: error))")
    return
  }

  let description = gybError.description
  // The format should be: "Error ... from filename\ncompiler output"
  // This ensures IDE error scrapers see compiler messages on their own lines
  let lines = description.split(separator: "\n", omittingEmptySubsequences: false)
  #expect(lines.count >= 2, "Error should have multiple lines")

  // First line should be our context message
  #expect(lines[0].contains("Error"))
  #expect(lines[0].contains("test.gyb"))

  // Remaining lines should be compiler/runtime output
  // (at least one non-empty line of actual error details)
  let hasCompilerOutput = lines.dropFirst().contains { !$0.isEmpty }
  #expect(hasCompilerOutput)
}

@Test("source location directives point to correct template lines")
func sourceLocation_correctLineNumbers() throws {
  let text = """
    Line 1: Hello
    Line 2: ${1 + 1}
    Line 3: World
    """

  let code = try generateCode(text, filename: "test.gyb")

  let expectedCode = #"""
    // Bindings


    // Template body
    #sourceLocation(file: "test.gyb", line: 1)
    print("""
    Line 1: Hello
    Line 2: \(1 + 1)
    Line 3: World
    """, terminator: "")

    """#
  #expect(code == expectedCode)
}

@Test("source location directives before code blocks point to correct lines")
func sourceLocation_codeBlocks() throws {
  let text = """
    output
    % let x = 42
    more output
    % let y = 100
    ${x + y}
    """

  let code = try generateCode(text, filename: "code.gyb")

  let expectedCode = #"""
    // Bindings


    // Template body
    #sourceLocation(file: "code.gyb", line: 1)
    print("""
    output

    """, terminator: "")
    #sourceLocation(file: "code.gyb", line: 2)
    let x = 42
    #sourceLocation(file: "code.gyb", line: 3)
    print("""
    more output

    """, terminator: "")
    #sourceLocation(file: "code.gyb", line: 4)
    let y = 100
    #sourceLocation(file: "code.gyb", line: 5)
    print("""
    \(x + y)
    """, terminator: "")

    """#
  #expect(code == expectedCode)
}

@Test("source location directives don't break multi-line code")
func sourceLocation_multiLineCode() throws {
  // Test that we handle multi-line code blocks correctly
  let text = """
    % func greet(name: String) -> String {
    %     return "Hello, \\(name)!"
    % }
    ${greet(name: "World")}
    """

  let code = try generateCode(text, filename: "multiline.gyb")

  let expectedCode = #"""
    // Bindings


    // Template body
    #sourceLocation(file: "multiline.gyb", line: 1)
    func greet(name: String) -> String {
    return "Hello, \(name)!"
    }
    #sourceLocation(file: "multiline.gyb", line: 4)
    print("""
    \(greet(name: "World"))
    """, terminator: "")

    """#
  #expect(code == expectedCode)

  // Verify the code compiles and executes
  let ast = try AST(filename: "multiline.gyb", template: text)
  let generator = CodeGenerator(template: text, filename: "multiline.gyb")
  let swiftCode = generator.generateCompleteProgram(ast, bindings: [:])
  let runner = SwiftScriptRunner(filename: "multiline.gyb")
  let result = try runner.execute(swiftCode)
  #expect(result == "Hello, World!")
}

@Test("source location directives reference correct template line for compilation errors")
func sourceLocation_compilationErrorReferencesTemplateLine() throws {
  // Error on line 3 of the template
  let text = """
    Line 1: text
    Line 2: % let x = 10
    Line 3: % let y: InvalidType = 20
    Line 4: ${x + y}
    """

  let error = #expect(throws: (any Error).self) {
    try execute(text, filename: "mytemplate.gyb")
  }

  guard let gybError = error as? GYBError else {
    Issue.record("Expected GYBError, got \(type(of: error))")
    return
  }

  let description = gybError.description
  // Error should reference the template filename
  #expect(description.contains("mytemplate.gyb"))
  // Error should reference line 3 where the error occurs
  #expect(description.contains("mytemplate.gyb:3"))
}

@Test("source location directives reference correct template line for runtime errors")
func sourceLocation_runtimeErrorReferencesTemplateLine() throws {
  // Runtime error: fatalError is on line 2, called on line 4
  let text = """
    Line 1: text
    Line 2: % func crash() { fatalError("boom") }
    Line 3: more text
    Line 4: % crash()
    Line 5: end
    """

  let error = #expect(throws: (any Error).self) {
    try execute(text, filename: "crash.gyb")
  }

  guard let gybError = error as? GYBError else {
    Issue.record("Expected GYBError, got \(type(of: error))")
    return
  }

  let description = gybError.description
  // Error should reference the template filename
  #expect(description.contains("crash.gyb"))
  // Runtime error reports where fatalError is defined (line 2), not where it's called (line 4)
  #expect(description.contains("crash.gyb:2"))
}

// MARK: - CLI Integration Tests
// Note: ArgumentParser automatically formats and writes errors to stderr when invoked
// as a command-line tool. We test the error content by running the command programmatically.

@Test("CLI throws compilation errors")
func cli_compilationError() throws {
  let tempDir = FileManager.default.temporaryDirectory
  let testFile = tempDir.appendingPathComponent("bad_compile_\(UUID().uuidString).gyb")

  defer {
    try? FileManager.default.removeItem(at: testFile)
  }

  // Write template with compilation error
  let badTemplate = """
    % let x: NonexistentType = 42
    ${x}
    """
  // On Windows, atomically: true can cause file locking issues
  try badTemplate.write(to: testFile, atomically: !isWindows, encoding: .utf8)

  // Run command programmatically
  var command = try GYBSwift.parseAsRoot([testFile.path])

  let error = #expect(throws: (any Error).self) {
    try command.run()
  }

  // Check that it's a GYBError with expected content
  guard let gybError = error as? GYBError else {
    Issue.record("Expected GYBError, got \(type(of: error))")
    return
  }

  let description = gybError.description
  #expect(description.contains("executing"))
  #expect(description.contains(testFile.lastPathComponent))
  #expect(description.contains("NonexistentType") || description.contains("cannot find"))
}

@Test("CLI throws execution errors")
func cli_executionError() throws {
  let tempDir = FileManager.default.temporaryDirectory
  let testFile = tempDir.appendingPathComponent("runtime_error_\(UUID().uuidString).gyb")

  defer {
    try? FileManager.default.removeItem(at: testFile)
  }

  // Write template that crashes at runtime
  let crashTemplate = """
    % fatalError("deliberate crash")
    """
  // On Windows, atomically: true can cause file locking issues
  try crashTemplate.write(to: testFile, atomically: !isWindows, encoding: .utf8)

  // Run command programmatically
  var command = try GYBSwift.parseAsRoot([testFile.path])

  let error = #expect(throws: (any Error).self) {
    try command.run()
  }

  // Check that it's a GYBError with expected content
  guard let gybError = error as? GYBError else {
    Issue.record("Expected GYBError, got \(type(of: error))")
    return
  }

  let description = gybError.description
  #expect(description.contains("executing"))
  #expect(description.contains(testFile.lastPathComponent))
  #expect(
    description.contains("Fatal error") || description.contains("deliberate crash")
      || description.contains("Illegal"))
}
