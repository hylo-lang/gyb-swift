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
