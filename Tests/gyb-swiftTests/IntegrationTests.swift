import SwiftParser
import SwiftSyntax
import Testing

@testable import gyb_swift

@Test("realistic template with multiple features")
func integration_realisticTemplate() throws {
    let text = """
        // Generated file
        struct Example {
            let count = ${count}
        }
        """

    let result = try execute(text, bindings: ["count": "42"], filename: "test.gyb")

    let expected = """
        // Generated file
        struct Example {
            let count = 42
        }
        """
    #expect(result == expected)
}

@Test("execute Swift template with control flow using % }")
// Swift templates use Swift syntax with unmatched braces
func execute_swiftControlFlow() throws {
    let text = """
        % for i in 0..<3 {
        ${i}
        % }
        """

    let result = try execute(text, filename: "test.gyb")

    let expected = """
        0
        1
        2

        """
    #expect(result == expected)
}

@Test("execute template with if control flow")
func execute_swiftIf() throws {
    let text = """
        % let x = 5
        % if x > 3 {
        large
        % }
        """

    let result = try execute(text)

    #expect(result == "large\n")
}

@Test("execute template with nested control flow")
func execute_nestedControlFlow() throws {
    let text = """
        % for x in 1...2 {
        %   for y in 1...2 {
        (${x},${y})
        %   }
        % }
        """

    let result = try execute(text)

    let expected = """
        (1,1)
        (1,2)
        (2,1)
        (2,2)

        """
    #expect(result == expected)
}

@Test("template structure is preserved")
func integration_templateStructurePreservation() throws {
    let text = """
        Header

        Body content

        Footer
        """

    let result = try execute(text)

    #expect(result == text)
}

@Test("--template-generates-swift emits and fixes #sourceLocation directives")
func integration_templateGeneratesSwift() throws {
    // Test that when emitting #sourceLocation directives in the output,
    // they are automatically fixed when needed
    let text = """
        % let x = 1
        % if x == 1 {
        func foo() { print("one") }
        % } else {
        func foo() { print("other") }
        % }
        """

    // Generate with #sourceLocation directives in the output
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let generator = CodeGenerator(
        templateText: text,
        filename: "test.gyb",
        lineDirective: #"#sourceLocation(file: "\(file)", line: \(line))"#,
        emitLineDirectives: true
    )

    var result = try generator.execute(ast, bindings: [:])

    // Apply the fixing strategy (simulating --template-generates-swift behavior)
    result = fixSourceLocationPlacement(result)

    // Result should contain #sourceLocation directives
    #expect(result.contains("#sourceLocation"))

    // Result should be valid Swift (no orphaned directives causing parse errors)
    // We can verify this by checking that the fixed output can be parsed
    let sourceFile = Parser.parse(source: result)

    // If there are missing tokens, the parse failed
    var hasMissingTokens = false
    for token in sourceFile.tokens(viewMode: .sourceAccurate) {
        if token.presence == .missing {
            hasMissingTokens = true
            break
        }
    }

    #expect(!hasMissingTokens)
}
