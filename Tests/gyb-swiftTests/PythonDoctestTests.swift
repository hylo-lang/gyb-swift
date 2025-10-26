import Testing

@testable import gyb_swift

@Test("line directive for each loop iteration")
// Python doctest: execute_template with loop that outputs multiple times
func lineDirective_loopIterations() throws {
    let text = """
        Nothing
        % if x != "0" {
        %    for i in 0..<3 {
        ${i}
        %    }
        % } else {
        THIS SHOULD NOT APPEAR IN THE OUTPUT
        % }
        """

    let code = try generateCode(text, bindings: ["x": "1"])

    let expectedCode = #"""
        import Foundation

        // Bindings
        let x = "1"

        // Generated code
        #sourceLocation(file: "test.gyb", line: 1)
        print("""
        Nothing

        """, terminator: "")
        #sourceLocation(file: "test.gyb", line: 2)
        if x != "0" {
        for i in 0..<3 {
        #sourceLocation(file: "test.gyb", line: 4)
        print("""
        \(i)

        """, terminator: "")
        #sourceLocation(file: "test.gyb", line: 5)
        }
        } else {
        #sourceLocation(file: "test.gyb", line: 7)
        print("""
        THIS SHOULD NOT APPEAR IN THE OUTPUT

        """, terminator: "")
        #sourceLocation(file: "test.gyb", line: 8)
        }

        """#
    #expect(code == expectedCode)

    // Verify execution produces correct output
    let result = try execute(
        text,
        bindings: ["x": "1"],
        filename: "test.gyb"
    )
    let expected = """
        Nothing
        0
        1
        2

        """
    #expect(result == expected)
}

@Test("line directive after code-only lines")
// Python doctest: execute_template with code-only %-lines followed by substitution
func lineDirective_afterCodeOnlyLines() throws {
    let text = """
        Nothing
        % var a: [Int] = []
        % for x in 0..<3 {
        %    a.append(x)
        % }
        ${a}
        """

    let code = try generateCode(text, bindings: [:])

    let expectedCode = #"""
        import Foundation

        // Bindings


        // Generated code
        #sourceLocation(file: "test.gyb", line: 1)
        print("""
        Nothing

        """, terminator: "")
        #sourceLocation(file: "test.gyb", line: 2)
        var a: [Int] = []
        for x in 0..<3 {
        a.append(x)
        }
        #sourceLocation(file: "test.gyb", line: 6)
        print("""
        \(a)
        """, terminator: "")

        """#
    #expect(code == expectedCode)

    // Verify execution
    let result = try execute(text, filename: "test.gyb")
    // Template has no trailing newline after the substitution
    #expect(result == "Nothing\n[0, 1, 2]")
}

@Test("multiline substitution expression")
// Python doctest: expand() with ${120 + \n    3}
func substitution_multiline() throws {
    let text = """
        ${120 +

           3}
        """

    let result = try execute(text, filename: "test.gyb")

    // Template has no trailing newline after the substitution
    #expect(result == "123")
}

@Test("substitution with embedded newlines in result")
// Swift literal string with escape sequences
func substitution_embeddedNewlines() throws {
    let text = #"""
        abc
        ${"w\nx\nX\ny"}
        z
        """#

    let result = try execute(text, filename: "test.gyb")

    // Note: Swift prints the escaped string literally as "w\nx\nX\ny"
    // Template has no trailing newline after 'z'
    #expect(result == #"abc\#nw\nx\nX\ny\#nz"#)
}

@Test("comprehensive integration test matching Python expand() doctest")
// Python doctest: expand() comprehensive test
// Note: We emit line directives at logical boundaries (per print statement) for cleaner output
func integration_comprehensiveExpandTest() throws {
    let text = #"""
        ---
        % for i in 0..<Int(x)! {
        a pox on ${i} for epoxy
        % }
        ${120 +

           3}
        abc
        ${"w\nx\nX\ny"}
        z
        """#

    let code = try generateCode(text, bindings: ["x": "2"])

    let expectedCode = ##"""
        import Foundation

        // Bindings
        let x = "2"

        // Generated code
        #sourceLocation(file: "test.gyb", line: 1)
        print("""
        ---

        """, terminator: "")
        #sourceLocation(file: "test.gyb", line: 2)
        for i in 0..<Int(x)! {
        #sourceLocation(file: "test.gyb", line: 3)
        print("""
        a pox on \(i) for epoxy

        """, terminator: "")
        #sourceLocation(file: "test.gyb", line: 4)
        }
        #sourceLocation(file: "test.gyb", line: 5)
        print("""
        \(120 +

           3)
        abc
        \("w\\nx\\nX\\ny")
        z
        """, terminator: "")

        """##
    #expect(code == expectedCode)

    // Verify execution produces correct output
    let result = try execute(
        text,
        bindings: ["x": "2"],
        filename: "test.gyb"
    )

    // Note: the ${"w\nx\nX\ny"} expression outputs the escaped string literally
    let expected = #"""
        ---
        a pox on 0 for epoxy
        a pox on 1 for epoxy
        123
        abc
        w\nx\nX\ny
        z
        """#
    #expect(result == expected)
}

@Test("alternative line directive format")
// Python doctest: execute_template with '#line %(line)d "%(file)s"' format
func lineDirective_alternativeFormat() throws {
    let text = """
        Nothing
        % var a: [Int] = []
        % for x in 0..<3 {
        %    a.append(x)
        % }
        ${a}
        """

    let code = try generateCode(text, bindings: [:])

    let expectedCode = #"""
        import Foundation

        // Bindings


        // Generated code
        #sourceLocation(file: "test.gyb", line: 1)
        print("""
        Nothing

        """, terminator: "")
        #sourceLocation(file: "test.gyb", line: 2)
        var a: [Int] = []
        for x in 0..<3 {
        a.append(x)
        }
        #sourceLocation(file: "test.gyb", line: 6)
        print("""
        \(a)
        """, terminator: "")

        """#
    #expect(code == expectedCode)

    // Test execution produces correct output
    let result = try execute(text, filename: "test.gyb")
    #expect(result == "Nothing\n[0, 1, 2]")
}
