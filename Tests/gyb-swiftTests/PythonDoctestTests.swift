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

    // Verify exact generated code structure with line directives
    let expectedCode = #"""
        import Foundation

        // Bindings
        let x = "1"

        // Generated code
        //# line 1 "test.gyb"
        print("""
        Nothing

        """, terminator: "")
        if x != "0" {
        for i in 0..<3 {
        //# line 4 "test.gyb"
        print("""
        \(i)

        """, terminator: "")
        }
        } else {
        //# line 7 "test.gyb"
        print("""
        THIS SHOULD NOT APPEAR IN THE OUTPUT

        """, terminator: "")
        }

        """#
    #expect(code == expectedCode)

    // Verify execution produces correct output
    let result = try execute(
        text,
        bindings: ["x": "1"],
        filename: "test.gyb",
        lineDirective: #"//# line \(line) "\(file)""#
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

    // Verify exact generated code with line directives at correct positions
    let expectedCode = #"""
        import Foundation

        // Bindings


        // Generated code
        //# line 1 "test.gyb"
        print("""
        Nothing

        """, terminator: "")
        var a: [Int] = []
        for x in 0..<3 {
        a.append(x)
        }
        //# line 6 "test.gyb"
        print("""
        \(a)
        """, terminator: "")

        """#
    #expect(code == expectedCode)

    // Verify execution
    let result = try execute(
        text,
        filename: "test.gyb",
        lineDirective: #"//# line \(line) "\(file)""#
    )
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

    // Verify exact generated code with line directives at correct positions
    let expectedCode = ##"""
        import Foundation

        // Bindings
        let x = "2"

        // Generated code
        //# line 1 "test.gyb"
        print("""
        ---

        """, terminator: "")
        for i in 0..<Int(x)! {
        //# line 3 "test.gyb"
        print("""
        a pox on \(i) for epoxy

        """, terminator: "")
        }
        //# line 5 "test.gyb"
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
        filename: "test.gyb",
        lineDirective: #"//# line \(line) "\(file)""#
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

    let code = try generateCode(
        text,
        bindings: [:],
        lineDirective: #"#line \(line) "\(file)""#
    )

    // Verify exact generated code with alternative line directive format
    let expectedCode = #"""
        import Foundation

        // Bindings


        // Generated code
        #line 1 "test.gyb"
        print("""
        Nothing

        """, terminator: "")
        var a: [Int] = []
        for x in 0..<3 {
        a.append(x)
        }
        #line 6 "test.gyb"
        print("""
        \(a)
        """, terminator: "")

        """#
    #expect(code == expectedCode)
}
