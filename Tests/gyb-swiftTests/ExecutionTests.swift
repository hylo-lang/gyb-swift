import Testing

@testable import gyb_swift

@Test("execute simple literal template")
func execute_literalTemplate() throws {
    let text = "Hello, World!"
    let result = try execute(text)

    #expect(result == "Hello, World!")
}

@Test("execute template with escaped symbols")
func execute_templateWithEscapedSymbols() throws {
    let text = "Price: $$50"
    let result = try execute(text)

    #expect(result == "Price: $50")
}

@Test("substitution with bound variable")
func substitution_withSimpleBinding() throws {
    let text = "x = ${x}"
    let result = try execute(text, bindings: ["x": "42"])
    #expect(result == "x = 42")
}

@Test("empty template")
func execute_emptyTemplate() throws {
    let text = ""
    let result = try execute(text)

    #expect(result == "")
}

@Test("template with only whitespace")
func execute_whitespaceOnly() throws {
    let text = "   \n\t\n   "
    let result = try execute(text)

    #expect(result == text)
}

@Test("mixed literal and symbols")
func execute_mixedLiteralsAndSymbols() throws {
    let text = "Regular $$text with %%symbols"
    let result = try execute(text)

    #expect(result == "Regular $text with %symbols")
}

@Test("malformed substitutions handled gracefully")
func parse_malformedSubstitution() {
    let text = "${unclosed"

    // Should handle gracefully - either parse as literal or throw clear error
    do {
        _ = try execute(text)
    } catch {
        // Error is expected for malformed input
    }
}

@Test("multiple literals in sequence")
func execute_multipleLiterals() throws {
    let text = "First line\nSecond line\nThird line"
    let result = try execute(text)

    #expect(result == text)
}

@Test("line directive generation")
func execute_lineDirectives() throws {
    let text = "Line 1\nLine 2"

    // Test with custom line directive format
    let code = try generateCode(text, bindings: [:])

    // Verify exact generated code with line directives
    let expectedCode = """
        import Foundation

        // Bindings


        // Generated code
        //# line 1 "test.gyb"
        print(\"\"\"
        Line 1
        Line 2
        \"\"\", terminator: "")

        """
    #expect(code == expectedCode)

    // Test execution produces exact expected output
    let result = try execute(
        text,
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\""
    )
    #expect(result == "Line 1\nLine 2")
}
