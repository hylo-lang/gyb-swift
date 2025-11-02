import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import gyb_swift

// MARK: - Test Helpers

/// Tests that fixer transforms `input` to match `expected` and
/// that the adjusted directives point to the correct lines.
///
/// Verifies:
/// 1. Fixer produces the expected output
/// 2. Fixed output is syntactically valid
/// 3. `#sourceLocation` directives point to correct lines
///
/// For single-directive tests, automatically appends `assertLine(#)`.
/// For multi-directive tests, validates that each directive has an `assertLine(#)`.
func assertFixesCode(
  _ input: String, expected: String,
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
  var processedInput = input
  var processedExpected = expected

  // Count directives in expected output
  let directiveCount = countSourceLocationDirectives(expected)

  if directiveCount == 1 && !input.contains("assertLine(#)") {
    // Single directive without explicit assertLine: append automatically
    processedInput = input + "\nassertLine(#)"
    processedExpected = expected + "\nassertLine(#)"
  } else if directiveCount > 1 {
    // Multiple directives: validate that each has an assertLine
    let assertLineCount = input.components(separatedBy: "assertLine(#)").count - 1
    #expect(
      assertLineCount >= directiveCount,
      "Test with \(directiveCount) directives must have at least \(directiveCount) assertLine(#) calls",
      sourceLocation: sourceLocation
    )
  }

  #expect(
    hasSyntaxErrors(processedInput),
    "Test problem: the original input was valid",
    sourceLocation: sourceLocation
  )

  let fixed = fixSourceLocationPlacement(processedInput)

  #expect(fixed == processedExpected, sourceLocation: sourceLocation)

  #expect(
    !hasSyntaxErrors(fixed),
    "Fixed code should be syntactically valid",
    sourceLocation: sourceLocation
  )

  // Verify directives point to correct lines by running the code
  verifySourceLocationDirectives(fixed, sourceLocation: sourceLocation)
}

/// The number of `#sourceLocation` directives in `code`.
private func countSourceLocationDirectives(_ code: String) -> Int {
  return code.components(separatedBy: "#sourceLocation").count - 1
}

/// The line number specified in a `#sourceLocation` directive, or `nil` if not found.
private func extractLineNumber(_ directiveLine: String) -> Int? {
  let numberPattern = #"line: (\d+)"#
  guard let numberMatch = directiveLine.range(of: numberPattern, options: .regularExpression) else {
    return nil
  }

  let number = directiveLine[numberMatch]
  guard let colonIndex = number.firstIndex(of: ":") else { return nil }

  let afterColon = number[number.index(after: colonIndex)...].trimmingCharacters(
    in: .whitespaces)
  return Int(afterColon)
}

/// `lines` with `assertLine(#)` placeholders replaced with actual line numbers.
private func replaceAssertLinePlaceholders(_ lines: [String]) -> [String] {
  var result = lines
  var lastDirectiveLine: Int? = nil

  for i in 0..<result.count {
    if result[i].range(
      of: #"#sourceLocation\(file: "[^"]*", line: (\d+)\)"#, options: .regularExpression)
      != nil
    {
      lastDirectiveLine = extractLineNumber(result[i])
    }

    if result[i].contains("assertLine(#)"), let directiveLine = lastDirectiveLine {
      let linesSinceDirective =
        i
        - (result.firstIndex(where: {
          $0.contains("#sourceLocation") && $0.contains("line: \(directiveLine)")
        }) ?? 0)
      let expectedLine = directiveLine + linesSinceDirective - 1
      result[i] = result[i].replacingOccurrences(
        of: "assertLine(#)", with: "assertLine(\(expectedLine))")
    }
  }

  return result
}

/// Runs `swiftCode` as a script, recording a test failure if it exits with non-zero status.
private func runSwiftScript(
  _ swiftCode: String, sourceLocation: Testing.SourceLocation
) {
  #if os(Windows)
    let tempDir =
      ProcessInfo.processInfo.environment["TEMP"] ?? ProcessInfo.processInfo.environment[
        "TMP"] ?? "C:\\Windows\\Temp"
    let tempFile = "\(tempDir)\\test_source_location_\(UUID().uuidString).swift"
  #else
    let tempFile = "/tmp/test_source_location_\(UUID().uuidString).swift"
  #endif

  do {
    defer { try? FileManager.default.removeItem(atPath: tempFile) }

    // On Windows, atomically: true can cause file locking issues
    try swiftCode.write(toFile: tempFile, atomically: !isWindows, encoding: .utf8)

    let result = try resultsOfRunning(["swift", tempFile])

    if result.exitStatus != 0 {
      var diagnostics = "Exit code: \(result.exitStatus)"

      if !result.stdout.isEmpty {
        diagnostics += "\nStdout:\n\(result.stdout)"
      }

      if !result.stderr.isEmpty {
        diagnostics += "\nStderr:\n\(result.stderr)"
      }

      diagnostics += "\n\nGenerated Swift code:\n\(swiftCode)"

      #expect(
        Bool(false),
        "#sourceLocation directives do not map to correct lines\n\(diagnostics)",
        sourceLocation: sourceLocation
      )
    }
  } catch {
    #expect(
      Bool(false),
      "Failed to run Swift script: \(error)\nCode:\n\(swiftCode)",
      sourceLocation: sourceLocation
    )
  }
}

/// Verifies that `#sourceLocation` directives correctly map to original source lines.
///
/// Replaces `assertLine(#)` placeholders with correct line numbers and runs the code.
private func verifySourceLocationDirectives(
  _ code: String, sourceLocation: Testing.SourceLocation
) {
  let assertLineFunction = """
    func assertLine(_ expected: UInt, _ line: UInt = #line) { assert(line == expected) }

    """

  let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  let processedLines = replaceAssertLinePlaceholders(lines)
  let executable = assertLineFunction + processedLines.joined(separator: "\n")

  runSwiftScript(executable, sourceLocation: sourceLocation)
}

/// Tests that fixer doesn't modify valid code.
func assertLeavesValidCodeUnchanged(
  _ input: String,
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
  #expect(
    !hasSyntaxErrors(input),
    "Input should be valid Swift",
    sourceLocation: sourceLocation
  )

  let fixed = fixSourceLocationPlacement(input)

  #expect(fixed == input, "Valid code should remain unchanged", sourceLocation: sourceLocation)
}

/// Returns whether `code` has syntax errors according to SwiftSyntax.
func hasSyntaxErrors(_ code: String) -> Bool {
  let sourceFile = Parser.parse(source: code)

  // Check for missing tokens
  for token in sourceFile.tokens(viewMode: .sourceAccurate) {
    if token.presence == .missing {
      return true
    }
  }

  // Check for unexpected nodes (another indicator of syntax errors)
  class UnexpectedChecker: SyntaxVisitor {
    var hasUnexpected = false
    override func visit(_ node: UnexpectedNodesSyntax) -> SyntaxVisitorContinueKind {
      hasUnexpected = true
      return .skipChildren
    }
  }
  let checker = UnexpectedChecker(viewMode: .sourceAccurate)
  checker.walk(sourceFile)

  return checker.hasUnexpected
}

// MARK: - Unit Tests

@Test("Swift executable is accessible")
func swiftExecutableAccessible() throws {
  do {
    let result = try resultsOfRunning(["swift", "--version"])

    print("Swift version check - Exit code: \(result.exitStatus)")
    if !result.stdout.isEmpty {
      print("Swift version output:\n\(result.stdout)")
    }
    if !result.stderr.isEmpty {
      print("Swift version stderr:\n\(result.stderr)")
    }

    #expect(
      result.exitStatus == 0,
      "Swift executable should be accessible via PATH"
    )
  } catch {
    #expect(Bool(false), "Failed to execute swift --version: \(error)")
  }
}

@Test("directive between closing brace and else is fixed")
func sourceLocationFixer_betweenBraceAndElse() {
  let input = """
    if true {
        print("yes")
    }
    #sourceLocation(file: "test.gyb", line: 5)
    else {
        print("no")
    }
    """

  let expected = """
    if true {
        print("yes")
    }
    else {
    #sourceLocation(file: "test.gyb", line: 6)
        print("no")
    }
    """

  assertFixesCode(input, expected: expected)
}

@Test("directive between closing brace and catch is fixed")
func sourceLocationFixer_betweenBraceAndCatch() {
  let input = """
    enum E: Error { case e }
    do {
        throw E.e
    }
    #sourceLocation(file: "test.gyb", line: 6)
    catch {
        print("error")
    }
    """

  let expected = """
    enum E: Error { case e }
    do {
        throw E.e
    }
    catch {
    #sourceLocation(file: "test.gyb", line: 7)
        print("error")
    }
    """

  assertFixesCode(input, expected: expected)
}

@Test("directive at error position in array is fixed")
func sourceLocationFixer_directiveAtErrorPosition() {
  let input = """
    print(
      [01
      #sourceLocation(file: "foo", line: 3)
    , 2, 3]
    )
    """

  let expected = """
    print(
      [01
    , 2, 3]
    )
      #sourceLocation(file: "foo", line: 6)
    """

  assertFixesCode(input, expected: expected)
}

@Test("directive after error is moved")
func sourceLocationFixer_directiveAfterError() {
  let input = """
    if true {
    }
    #sourceLocation(file: "test.gyb", line: 4)
    else {
    }
    """

  let expected = """
    if true {
    }
    else {
    #sourceLocation(file: "test.gyb", line: 5)
    }
    """

  assertFixesCode(input, expected: expected)
}

@Test("directive with comments between is fixed")
func sourceLocationFixer_withComments() {
  let input = """
    if true {
    }
    // Comment before directive
    #sourceLocation(file: "test.gyb", line: 5)
    // Comment after directive
    else {
    }
    """

  let expected = """
    if true {
    }
    // Comment before directive
    // Comment after directive
    else {
    #sourceLocation(file: "test.gyb", line: 7)
    }
    """

  assertFixesCode(input, expected: expected)
}

@Test("multiple directives are fixed")
func sourceLocationFixer_multipleDirectives() {
  let input = """
    if true {
    }
    #sourceLocation(file: "test.gyb", line: 4)
    else if false {
        assertLine(#)
    }
    #sourceLocation(file: "test.gyb", line: 7)
    else {
        assertLine(#)
    }
    """

  let expected = """
    if true {
    }
    else if false {
    #sourceLocation(file: "test.gyb", line: 5)
        assertLine(#)
    }
    else {
    #sourceLocation(file: "test.gyb", line: 9)
        assertLine(#)
    }
    """

  assertFixesCode(input, expected: expected)
}

@Test("valid code with directives is unchanged")
func sourceLocationFixer_validCodeUnchanged() {
  let input = """
    if true {
    #sourceLocation(file: "test.gyb", line: 2)
        print("yes")
    }
    else {
    #sourceLocation(file: "test.gyb", line: 5)
        print("no")
    }
    """

  assertLeavesValidCodeUnchanged(input)
}

@Test("directive before switch case is fixed")
func sourceLocationFixer_beforeSwitchCase() {
  let input = """
    let x = 1
    switch x {
    #sourceLocation(file: "test.gyb", line: 3)
    case 1:
        print("one")
    default:
        print("default")
    }
    """

  let expected = """
    let x = 1
    switch x {
    case 1:
    #sourceLocation(file: "test.gyb", line: 5)
        print("one")
    default:
        print("default")
    }
    """

  assertFixesCode(input, expected: expected)
}
