import Testing

@testable import gyb_swift

@Test("execute simple literal template")
func execute_literalTemplate() throws {
  #expect(try execute("Hello, World!") == "Hello, World!")
}

@Test("execute template with escaped symbols")
func execute_templateWithEscapedSymbols() throws {
  #expect(try execute("Price: $$50") == "Price: $50")
}

@Test("substitution with bound variable")
func substitution_withSimpleBinding() throws {
  #expect(try execute("x = ${x}", bindings: ["x": "42"]) == "x = 42")
}

@Test("empty template")
func execute_emptyTemplate() throws {
  #expect(try execute("") == "")
}

@Test("template with only whitespace")
func execute_whitespaceOnly() throws {
  let text = "   \n\t\n   "
  #expect(try execute(text) == text)
}

@Test("mixed literal and symbols")
func execute_mixedLiteralsAndSymbols() throws {
  #expect(try execute("Regular $$text with %%symbols") == "Regular $text with %symbols")
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
  #expect(try execute(text) == text)
}

@Test("line directive generation")
func execute_lineDirectives() throws {
  let text = "Line 1\nLine 2"

  // Verify exact generated code structure
  let code = try generateCode(text, bindings: [:])
  let expectedCode = #"""
    // Bindings


    // Template body
    #sourceLocation(file: "test.gyb", line: 1)
    print("""
    Line 1
    Line 2
    """, terminator: "")

    """#
  #expect(code == expectedCode)

  // Test execution produces exact expected output (no line directives in output)
  let result = try execute(text, filename: "test.gyb")
  #expect(result == "Line 1\nLine 2")
}

// MARK: - Known Limitations

@Test("template with output between } and else creates invalid Swift - cannot be fixed")
func sourceLocation_templateGeneratesOrphanedElse() throws {
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
