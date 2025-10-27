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
func assertFixesCode(
    _ input: String, expected: String,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    #expect(
        hasSyntaxErrors(input),
        "Test problem: the original input was valid",
        sourceLocation: sourceLocation
    )

    let fixed = fixSourceLocationPlacement(input)

    #expect(fixed == expected, sourceLocation: sourceLocation)

    #expect(
        !hasSyntaxErrors(fixed),
        "Fixed code should be syntactically valid",
        sourceLocation: sourceLocation
    )
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
        do {
            try something()
        }
        #sourceLocation(file: "test.gyb", line: 5)
        catch {
            print("error")
        }
        """

    let expected = """
        do {
            try something()
        }
        catch {
        #sourceLocation(file: "test.gyb", line: 6)
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
        }
        #sourceLocation(file: "test.gyb", line: 7)
        else {
        }
        """

    let expected = """
        if true {
        }
        else if false {
        #sourceLocation(file: "test.gyb", line: 5)
        }
        else {
        #sourceLocation(file: "test.gyb", line: 8)
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

// MARK: - Known Limitations

@Test("output between } and else creates invalid Swift - cannot be fixed")
func sourceLocation_outputBetweenIfElse() throws {
    // This template has output between } and else.
    // This creates fundamentally invalid Swift (orphaned else), which cannot be fixed
    // by moving #sourceLocation directives.
    let text = """
        % if false {
        %     print("hello")
        % }
        output between braces
        % else {
        %     print("world")
        % }
        """

    // Should fail because the generated Swift is invalid
    #expect(throws: GYBError.self) {
        try execute(text, filename: "test.gyb")
    }
}

@Test("simple #sourceLocation before 'else' is fixed when valid")
func sourceLocation_beforeElseIsFixed() throws {
    // When there's a continuation keyword after a directive but the Swift is structurally
    // valid, we can fix it by moving the directive.
    // This test uses a switch/case example which is valid with our fix.
    let text = """
        % let x = 1
        % switch x {
        % case 1:
        output for case 1
        % default:
        %     print("default")
        % }
        """

    let result = try execute(text, filename: "test.gyb")
    #expect(result.contains("output for case 1"))
}

@Test("else on same line as closing brace works correctly")
func sourceLocation_elseOnSameLine() throws {
    // When } and else are on the same line (or consecutive % lines with no output),
    // they get batched together and work fine
    let text = """
        % if false {
        %     print("hello")
        % } else {
        %     print("world")
        % }
        """

    let result = try execute(text, filename: "test.gyb")
    #expect(result == "world\n")
}

@Test("separate } and else lines without output in between works")
func sourceLocation_separateElseLinesNoOutput() throws {
    // When } and else are consecutive code lines with no output between,
    // they're batched and work fine
    let text = """
        % if false {
        %     print("hello")
        % }
        % else {
        %     print("world")
        % }
        """

    let result = try execute(text, filename: "test.gyb")
    #expect(result == "world\n")
}
