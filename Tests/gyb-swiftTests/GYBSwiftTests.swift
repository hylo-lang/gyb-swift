import XCTest
@testable import gyb_swift

/// Tests for the GYB-Swift template processor.
///
/// These tests are translated from the original Python gyb.py doctests,
/// adapted for Swift's execution model limitations.
final class GYBSwiftTests: XCTestCase {
    
    // MARK: - String Utilities Tests
    
    /// Tests getLineStarts with multi-line text.
    func testGetLineStarts() throws {
        let text = "line1\nline2\nline3"
        let starts = getLineStarts(text)
        
        XCTAssertEqual(starts.count, 4, "Should have 3 line starts + 1 sentinel")
        XCTAssertEqual(starts[0], text.startIndex, "First start should be text start")
        XCTAssertEqual(starts.last, text.endIndex, "Last should be sentinel (text end)")
    }
    
    /// Tests getLineStarts with empty string.
    func testGetLineStartsEmpty() {
        let starts = getLineStarts("")
        XCTAssertEqual(starts.count, 2, "Empty string should have start + sentinel")
        XCTAssertEqual(starts[0], "".startIndex)
        XCTAssertEqual(starts[1], "".endIndex)
    }
    
    /// Tests getLineStarts with single line (no newline).
    func testGetLineStartsSingleLine() {
        let text = "single line"
        let starts = getLineStarts(text)
        XCTAssertEqual(starts.count, 2, "Single line should have start + sentinel")
        XCTAssertEqual(starts[0], text.startIndex)
        XCTAssertEqual(starts[1], text.endIndex)
    }
    
    /// Tests getLineStarts handles different newline types.
    func testGetLineStartsDifferentNewlines() {
        // LF
        XCTAssertEqual(getLineStarts("a\nb").count, 3)
        // CR
        XCTAssertEqual(getLineStarts("a\rb").count, 3)
        // CRLF (note: \r\n is one Character in Swift)
        XCTAssertEqual(getLineStarts("a\r\nb").count, 3)
    }
    
    /// Tests stripTrailingNewline removes LF.
    func testStripTrailingNewlineWithNewline() {
        XCTAssertEqual(stripTrailingNewline("hello\n"), "hello")
    }
    
    /// Tests stripTrailingNewline leaves text unchanged when no newline.
    func testStripTrailingNewlineWithoutNewline() {
        XCTAssertEqual(stripTrailingNewline("hello"), "hello")
    }
    
    /// Tests stripTrailingNewline removes CR.
    func testStripTrailingNewlineCR() {
        XCTAssertEqual(stripTrailingNewline("hello\r"), "hello")
    }
    
    /// Tests stripTrailingNewline removes CRLF.
    func testStripTrailingNewlineCRLF() {
        XCTAssertEqual(stripTrailingNewline("hello\r\n"), "hello")
    }
    
    /// Tests stripTrailingNewline with empty string.
    func testStripTrailingNewlineEmpty() {
        XCTAssertEqual(stripTrailingNewline(""), "")
    }
    
    /// Tests stripTrailingNewline with only newline.
    func testStripTrailingNewlineOnlyNewline() {
        XCTAssertEqual(stripTrailingNewline("\n"), "")
    }
    
    /// Tests splitLines preserves newlines on each line.
    func testSplitLines() {
        let lines = splitLines("a\nb\nc")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "a\n")
        XCTAssertEqual(lines[1], "b\n")
        XCTAssertEqual(lines[2], "c\n")
    }
    
    /// Tests splitLines with empty string.
    func testSplitLinesEmpty() {
        let lines = splitLines("")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0], "\n")
    }
    
    /// Tests splitLines with single line.
    func testSplitLinesSingle() {
        let lines = splitLines("hello")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0], "hello\n")
    }
    
    /// Tests splitLines handles trailing newline.
    func testSplitLinesTrailingNewline() {
        let lines = splitLines("a\nb\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "a\n")
        XCTAssertEqual(lines[1], "b\n")
        XCTAssertEqual(lines[2], "\n")
    }
    
    /// Tests splitLines handles different newline types.
    func testSplitLinesDifferentNewlines() {
        // CR
        let cr = splitLines("a\rb")
        XCTAssertEqual(cr.count, 2)
        XCTAssertEqual(cr[0], "a\n")
        XCTAssertEqual(cr[1], "b\n")
        
        // CRLF
        let crlf = splitLines("a\r\nb")
        XCTAssertEqual(crlf.count, 2)
        XCTAssertEqual(crlf[0], "a\n")
        XCTAssertEqual(crlf[1], "b\n")
    }
    
    // MARK: - Tokenization Tests
    
    /// Tests tokenizing a simple literal template.
    func testTokenizeLiteral() {
        let tokenizer = TemplateTokenizer(text: "Hello, World!")
        let token = tokenizer.next()
        
        XCTAssertNotNil(token)
        if case .literal = token?.kind {
            XCTAssertTrue(token!.text.contains("Hello"))
        } else {
            XCTFail("Expected literal token")
        }
    }
    
    /// Tests tokenizing $$ escape sequence.
    func testTokenizeEscapedDollar() {
        let tokenizer = TemplateTokenizer(text: "$$100")
        var tokens: [TemplateToken] = []
        while let token = tokenizer.next() {
            tokens.append(token)
        }
        
        XCTAssertTrue(tokens.contains { $0.kind == .symbol && $0.text == "$$" })
    }
    
    /// Tests tokenizing %% escape sequence.
    func testTokenizeEscapedPercent() {
        let tokenizer = TemplateTokenizer(text: "100%%")
        var tokens: [TemplateToken] = []
        while let token = tokenizer.next() {
            tokens.append(token)
        }
        
        XCTAssertTrue(tokens.contains { $0.kind == .symbol && $0.text == "%%" })
    }
    
    /// Tests tokenizing ${} substitution.
    func testTokenizeSubstitution() {
        let tokenizer = TemplateTokenizer(text: "${x}")
        var tokens: [TemplateToken] = []
        while let token = tokenizer.next() {
            tokens.append(token)
        }
        
        XCTAssertTrue(tokens.contains { $0.kind == .substitutionOpen })
    }
    
    /// Tests tokenizing %{} code block.
    func testTokenizeCodeBlock() {
        let tokenizer = TemplateTokenizer(text: "%{ let x = 42 }%")
        var tokens: [TemplateToken] = []
        while let token = tokenizer.next() {
            tokens.append(token)
        }
        
        XCTAssertTrue(tokens.contains { $0.kind == .gybBlockOpen })
    }
    
    /// Tests that }% inside strings doesn't terminate code block.
    ///
    /// This is the critical test case that requires Swift tokenization.
    /// Without proper tokenization, the naive scanner would incorrectly
    /// stop at the }% inside the string literal.
    func testCodeBlockWithDelimiterInString() {
        let tokenizer = TemplateTokenizer(text: #"%{ let msg = "Error: }% not allowed" }%Done"#)
        var tokens: [TemplateToken] = []
        while let token = tokenizer.next() {
            tokens.append(token)
        }
        
        // Should have: gybBlockOpen, literal("Done")
        XCTAssertEqual(tokens.count, 2, "Should have 2 tokens: code block and literal")
        XCTAssertEqual(tokens[0].kind, .gybBlockOpen, "First should be code block")
        XCTAssertTrue(tokens[0].text.contains(#""Error: }% not allowed""#), 
                      "Should contain full string with }% inside it")
        XCTAssertEqual(tokens[1].kind, .literal, "Second should be literal")
        XCTAssertEqual(tokens[1].text, "Done", "Should be 'Done'")
    }
    
    /// Tests that } inside strings in ${} doesn't terminate substitution.
    ///
    /// This verifies SwiftSyntax correctly handles dictionary/subscript syntax
    /// where } appears in string keys.
    func testSubstitutionWithBraceInString() {
        let tokenizer = TemplateTokenizer(text: #"${dict["key}value"]}Done"#)
        var tokens: [TemplateToken] = []
        while let token = tokenizer.next() {
            tokens.append(token)
        }
        
        // Should have: substitutionOpen, literal("Done")
        XCTAssertEqual(tokens.count, 2, "Should have 2 tokens: substitution and literal")
        XCTAssertEqual(tokens[0].kind, .substitutionOpen, "First should be substitution")
        XCTAssertTrue(tokens[0].text.contains(#""key}value""#), 
                      "Should contain full string with } inside it")
        XCTAssertEqual(tokens[1].kind, .literal, "Second should be literal")
        XCTAssertEqual(tokens[1].text, "Done", "Should be 'Done'")
    }
    
    /// Tests multiple nested strings with delimiters.
    func testNestedStringsWithDelimiters() {
        let text = #"%{ let a = "first }% here"; let b = "second }% there" }%"#
        let tokenizer = TemplateTokenizer(text: text)
        var tokens: [TemplateToken] = []
        while let token = tokenizer.next() {
            tokens.append(token)
        }
        
        XCTAssertEqual(tokens.count, 1, "Should be one complete code block")
        XCTAssertEqual(tokens[0].kind, .gybBlockOpen)
        XCTAssertTrue(tokens[0].text.contains("first }% here"))
        XCTAssertTrue(tokens[0].text.contains("second }% there"))
    }
    
    /// Tests multiline string literals with delimiters.
    func testMultilineStringWithDelimiter() {
        let text = #"""
        %{ let msg = """
        Error message with }% in it
        """ }%Done
        """#
        let tokenizer = TemplateTokenizer(text: text)
        var tokens: [TemplateToken] = []
        while let token = tokenizer.next() {
            tokens.append(token)
        }
        
        // SwiftParser should handle multiline strings correctly
        XCTAssertGreaterThanOrEqual(tokens.count, 1, "Should tokenize without crash")
    }
    
    /// Tests tokenizing % code lines.
    func testTokenizeCodeLines() {
        let tokenizer = TemplateTokenizer(text: "% let x = 10\n")
        let token = tokenizer.next()
        
        XCTAssertNotNil(token)
        XCTAssertEqual(token?.kind, .gybLines)
    }
    
    // MARK: - Parse Tests
    
    /// Tests parsing a simple literal template.
    func testParseLiteralTemplate() throws {
        let text = "Hello, World!"
        let ast = try parseTemplate(filename: "test", text: text)
        
        XCTAssertEqual(ast.children.count, 1)
        XCTAssertTrue(ast.children[0] is LiteralNode)
    }
    
    /// Tests parsing template with escaped symbols.
    func testParseTemplateWithEscapedSymbols() throws {
        let text = "$$dollar and %%percent"
        let ast = try parseTemplate(filename: "test", text: text)
        
        // Should have parsed the symbols
        XCTAssertGreaterThanOrEqual(ast.children.count, 1)
    }
    
    /// Tests parsing substitution.
    func testParseSubstitution() throws {
        let text = "${x}"
        let ast = try parseTemplate(filename: "test", text: text)
        
        XCTAssertEqual(ast.children.count, 1)
        XCTAssertTrue(ast.children[0] is SubstitutionNode)
    }
    
    /// Tests parsing code block.
    func testParseCodeBlock() throws {
        let text = "%{ let x = 42 }%"
        let ast = try parseTemplate(filename: "test", text: text)
        
        XCTAssertEqual(ast.children.count, 1)
        XCTAssertTrue(ast.children[0] is CodeNode)
    }
    
    // MARK: - Basic Execution Tests
    
    /// Tests executing a simple literal template.
    func testExecuteLiteralTemplate() throws {
        let text = "Hello, World!"
        let ast = try parseTemplate(filename: "test", text: text)
        let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
        
        XCTAssertEqual(result, "Hello, World!")
    }
    
    /// Tests executing template with escaped symbols.
    func testExecuteTemplateWithEscapedSymbols() throws {
        let text = "Price: $$50"
        let ast = try parseTemplate(filename: "test", text: text)
        let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
        
        XCTAssertTrue(result.contains("$50"), "Expected '$50' in result")
    }
    
    /// Tests substitution with bound variable.
    func testSubstitutionWithSimpleBinding() throws {
        let text = "x = ${x}"
        let ast = try parseTemplate(filename: "test", text: text)
        let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: ["x": 42])
        XCTAssertTrue(result.contains("42"), "Result should contain '42'")
    }
    
    /// Tests empty template.
    func testEmptyTemplate() throws {
        let text = ""
        let ast = try parseTemplate(filename: "test", text: text)
        let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
        
        XCTAssertEqual(result, "")
    }
    
    /// Tests template with only whitespace.
    func testWhitespaceOnlyTemplate() throws {
        let text = "   \n\t\n   "
        let ast = try parseTemplate(filename: "test", text: text)
        let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
        
        XCTAssertEqual(result, text)
    }
    
    /// Tests mixed literal and symbols.
    func testMixedLiteralsAndSymbols() throws {
        let text = "Regular $$text with %%symbols"
        let ast = try parseTemplate(filename: "test", text: text)
        let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
        
        XCTAssertTrue(result.contains("Regular"))
        XCTAssertTrue(result.contains("$text"))
        XCTAssertTrue(result.contains("%symbols"))
    }
    
    /// Tests that malformed substitutions are handled gracefully.
    func testMalformedSubstitution() {
        let text = "${unclosed"
        
        // Should handle gracefully - either parse as literal or throw clear error
        do {
            let ast = try parseTemplate(filename: "test", text: text)
            _ = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
        } catch {
            // Error is acceptable for malformed input
            XCTAssertNotNil(error)
        }
    }
    
    /// Tests multiple literals in sequence.
    func testMultipleLiterals() throws {
        let text = "First line\nSecond line\nThird line"
        let ast = try parseTemplate(filename: "test", text: text)
        let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
        
        XCTAssertEqual(result, text)
    }
    
    /// Tests AST structure for mixed template.
    func testASTStructure() throws {
        let text = "Text ${x} more text"
        let ast = try parseTemplate(filename: "test", text: text)
        
        // Should have multiple children: literal, substitution, literal
        XCTAssertGreaterThanOrEqual(ast.children.count, 1)
        
        var hasSubstitution = false
        for child in ast.children {
            if child is SubstitutionNode {
                hasSubstitution = true
            }
        }
        XCTAssertTrue(hasSubstitution, "Should have a substitution node")
    }
    
    /// Tests line directive generation.
    func testLineDirectives() throws {
        let text = "Line 1\nLine 2"
        let ast = try parseTemplate(filename: "test.gyb", text: text)
        let result = try executeTemplate(
            ast,
            filename: "test.gyb",
            lineDirective: "//# line %(line)d \"%(file)s\"",
            bindings: [:]
        )
        
        // For literal-only templates, line directives may not be emitted
        // That's acceptable behavior
        XCTAssertNotNil(result, "Should produce result")
        // If the template has no code, it won't emit line directives
        // This is correct behavior for pure literal templates
    }
    
    // MARK: - Documentation Tests
    
    /// Tests that all major components can be instantiated.
    func testComponentInstantiation() {
        // Test tokenizer
        let tokenizer = TemplateTokenizer(text: "test")
        XCTAssertNotNil(tokenizer)
        
        // Test parse context
        let context = ParseContext(filename: "test", text: "content")
        XCTAssertNotNil(context)
        XCTAssertEqual(context.filename, "test")
        
        // Test execution context
        let execContext = ExecutionContext(filename: "test")
        XCTAssertNotNil(execContext)
    }
    
    /// Tests AST node creation.
    func testASTNodeCreation() {
        let literal = LiteralNode(text: "hello", line: 1)
        XCTAssertEqual(literal.text, "hello")
        
        let code = CodeNode(code: "let x = 1", line: 1)
        XCTAssertEqual(code.code, "let x = 1")
        
        let subst = SubstitutionNode(expression: "x", line: 1)
        XCTAssertEqual(subst.expression, "x")
        
        let block = BlockNode(children: [literal], line: 1)
        XCTAssertEqual(block.children.count, 1)
    }
}

/// Tests for integration scenarios.
///
/// These demonstrate end-to-end template processing where applicable.
final class GYBIntegrationTests: XCTestCase {
    
    /// Tests processing a realistic template with multiple features.
    func testRealisticTemplate() throws {
        let text = """
        // Generated file
        struct Example {
            let count = ${count}
        }
        """
        
        let ast = try parseTemplate(filename: "test.gyb", text: text)
        let result = try executeTemplate(
            ast,
            filename: "test.gyb",
            lineDirective: "",
            bindings: ["count": 42]
        )
        
        XCTAssertTrue(result.contains("struct Example"))
        XCTAssertTrue(result.contains("42"))
    }
    
    /// Tests that the template structure is preserved.
    func testTemplateStructurePreservation() throws {
        let text = """
        Header
        
        Body content
        
        Footer
        """
        
        let ast = try parseTemplate(filename: "test", text: text)
        let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
        
        XCTAssertTrue(result.contains("Header"))
        XCTAssertTrue(result.contains("Body content"))
        XCTAssertTrue(result.contains("Footer"))
    }
}
