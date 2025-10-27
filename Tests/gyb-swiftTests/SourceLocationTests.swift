import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import gyb_swift

// MARK: - Test Helpers

/// Tests that fixer transforms `input` to match `expected`.
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
    let directiveCount = countSourceLocationDirectives(in: expected)

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

    // Verify directives work correctly if assertLine(#) is present
    if fixed.contains("assertLine(#)") {
        verifySourceLocationDirectives(fixed, sourceLocation: sourceLocation)
    }
}

/// The number of `#sourceLocation` directives in `code`.
private func countSourceLocationDirectives(in code: String) -> Int {
    return code.components(separatedBy: "#sourceLocation").count - 1
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

    var lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    // Process each line to replace assertLine(#) with correct line number
    var lastDirectiveLine: Int? = nil
    for i in 0..<lines.count {
        // Check if this line contains a #sourceLocation directive
        if lines[i].range(of: #"#sourceLocation\(file: "[^"]*", line: (\d+)\)"#, options: .regularExpression) != nil {
            let numberPattern = #"line: (\d+)"#
            if let numberMatch = lines[i].range(of: numberPattern, options: .regularExpression) {
                let numberText = lines[i][numberMatch]
                if let colonIndex = numberText.firstIndex(of: ":") {
                    let afterColon = numberText[numberText.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                    if let lineNum = Int(afterColon) {
                        lastDirectiveLine = lineNum
                    }
                }
            }
        }

        // Check if this line contains assertLine(#)
        if lines[i].contains("assertLine(#)"), let directiveLine = lastDirectiveLine {
            // Count lines from directive to this assertLine call
            // The directive points to the line after it appears
            let linesSinceDirective = i - (lines.firstIndex(where: { $0.contains("#sourceLocation") && $0.contains("line: \(directiveLine)") }) ?? 0)
            let expectedLine = directiveLine + linesSinceDirective - 1
            lines[i] = lines[i].replacingOccurrences(of: "assertLine(#)", with: "assertLine(\(expectedLine))")
        }
    }

    let executable = assertLineFunction + lines.joined(separator: "\n")

    // Run the code as a Swift script
    let tempFile = "/tmp/test_source_location_\(UUID().uuidString).swift"
    do {
        try executable.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [tempFile]
        try process.run()
        process.waitUntilExit()

        #expect(
            process.terminationStatus == 0,
            "#sourceLocation directives do not map to correct lines",
            sourceLocation: sourceLocation
        )
    } catch {
        Issue.record(
            "Failed to verify source location directives: \(error)",
            sourceLocation: sourceLocation
        )
    }
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
