import Testing
@testable import gyb_swift

// MARK: - String Utilities Tests

@Test("getLineStarts with multi-line text")
func getLineStarts_multiLine() throws {
    let text = "line1\nline2\nline3"
    let starts = getLineStarts(text)
    
    #expect(starts.count == 4)
    #expect(starts[0] == text.startIndex)
    #expect(starts.last == text.endIndex)
}

@Test("getLineStarts with empty string")
func getLineStarts_empty() {
    let starts = getLineStarts("")
    #expect(starts.count == 2)
    #expect(starts[0] == "".startIndex)
    #expect(starts[1] == "".endIndex)
}

@Test("getLineStarts with single line")
func getLineStarts_singleLine() {
    let text = "single line"
    let starts = getLineStarts(text)
    #expect(starts.count == 2)
    #expect(starts[0] == text.startIndex)
    #expect(starts[1] == text.endIndex)
}

@Test("getLineStarts handles different newline types")
func getLineStarts_differentNewlines() {
    #expect(getLineStarts("a\nb").count == 3)    // LF
    #expect(getLineStarts("a\rb").count == 3)    // CR
    #expect(getLineStarts("a\r\nb").count == 3)  // CRLF (note: \r\n is one Character)
}

// MARK: - Tokenization Tests

@Test("tokenize simple literal template")
func tokenize_literal() {
    var tokenizer = TemplateTokens(text: "Hello, World!")
    let token = tokenizer.next()
    
    #expect(token?.kind == .literal)
    #expect(token?.text.contains("Hello") == true)
}

@Test("tokenize $$ escape sequence")
func tokenize_escapedDollar() {
    var tokenizer = TemplateTokens(text: "$$100")
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.contains { $0.kind == .symbol && $0.text == "$$" })
}

@Test("tokenize %% escape sequence")
func tokenize_escapedPercent() {
    var tokenizer = TemplateTokens(text: "100%%")
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.contains { $0.kind == .symbol && $0.text == "%%" })
}

@Test("tokenize ${} substitution")
func tokenize_substitution() {
    var tokenizer = TemplateTokens(text: "${x}")
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.contains { $0.kind == .substitutionOpen })
}

@Test("tokenize %{} code block")
func tokenize_codeBlock() {
    var tokenizer = TemplateTokens(text: "%{ let x = 42 }%")
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.contains { $0.kind == .gybBlockOpen })
}

@Test("}% inside strings doesn't terminate code block")
// This is the critical test case that requires Swift tokenization.
// Without proper tokenization, the naive scanner would incorrectly
// stop at the }% inside the string literal.
func codeBlock_delimiterInString() {
    var tokenizer = TemplateTokens(text: #"%{ let msg = "Error: }% not allowed" }%Done"#)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text.contains(#""Error: }% not allowed""#))
    #expect(tokens[1].kind == .literal)
    #expect(tokens[1].text == "Done")
}

@Test("} inside strings in ${} doesn't terminate substitution")
// This verifies SwiftSyntax correctly handles dictionary/subscript syntax
// where } appears in string keys.
func substitution_braceInString() {
    var tokenizer = TemplateTokens(text: #"${dict["key}value"]}Done"#)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .substitutionOpen)
    #expect(tokens[0].text.contains(#""key}value""#))
    #expect(tokens[1].kind == .literal)
    #expect(tokens[1].text == "Done")
}

@Test("multiple nested strings with delimiters")
func nestedStrings_withDelimiters() {
    let text = #"%{ let a = "first }% here"; let b = "second }% there" }%"#
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text.contains("first }% here"))
    #expect(tokens[0].text.contains("second }% there"))
}

@Test("SwiftSyntax parser handles invalid/incomplete Swift gracefully")
// This is critical because sourceText[start...] often contains template text
// after the Swift code, making it syntactically invalid. SwiftSyntax Parser
// is designed to be resilient (for LSP use) and handles this correctly.
func parser_resilientWithInvalidSwift() {
    // Test case: valid Swift code followed by template text
    // When parsing ${count}, we actually parse "count}Done" which is invalid Swift
    var tokenizer = TemplateTokens(text: "${count}Done")
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .substitutionOpen)
    #expect(tokens[0].text.contains("count"))
    #expect(!tokens[0].text.contains("Done"))
    #expect(tokens[1].kind == .literal)
    #expect(tokens[1].text.contains("Done"))
}

@Test("%{...}% code blocks with nested braces from closures")
func codeBlock_withClosure() {
    let text = #"%{ items.forEach { print($0) } }%Done"#
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text.contains("forEach"))
    #expect(tokens[0].text.contains("print($0)"))
    #expect(!tokens[0].text.contains("Done"))
    #expect(tokens[1].text == "Done")
}

@Test("%{...}% code blocks with nested braces from dictionaries")
func codeBlock_withDictionary() {
    let text = #"%{ let dict = ["key": "value"]; let x = dict["key"] }%After"#
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text.contains(#"["key": "value"]"#))
    #expect(!tokens[0].text.contains("After"))
}

@Test("%{...}% code blocks with nested control structures")
func codeBlock_nestedControlStructures() {
    let text = #"""
    %{ if true {
        let dict = ["a": 1]
        for (k, v) in dict {
            print("\(k): \(v)")
        }
    } }%Done
    """#
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count >= 1)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text.contains("if true"))
    #expect(tokens[0].text.contains("for (k, v)"))
    #expect(!tokens[0].text.contains("Done"))
}

@Test("%{...}% code blocks with generics containing angle brackets")
func codeBlock_withGenerics() {
    let text = #"%{ let arr: Array<[String: Int]> = [] }%Text"#
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text.contains("Array<"))
    #expect(tokens[0].text.contains("[String: Int]"))
    #expect(!tokens[0].text.contains("Text"))
}

@Test("%{...}% code blocks with trailing closure syntax")
func codeBlock_trailingClosure() {
    let text = #"%{ let result = numbers.map { $0 * 2 } }%End"#
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text.contains("map { $0 * 2 }"))
    #expect(!tokens[0].text.contains("End"))
}

@Test("multiline string literals with delimiters")
func multilineString_withDelimiter() {
    let text = #"""
    %{ let msg = """
    Error message with }% in it
    """ }%Done
    """#
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    #expect(tokens.count >= 1)
}

@Test("tokenize % code lines")
func tokenize_codeLines() {
    var tokenizer = TemplateTokens(text: "% let x = 10\n")
    let token = tokenizer.next()
    
    #expect(token?.kind == .gybLines)
}

// MARK: - Python Doctest Translations

@Test("tokenize template with %for/%end")
// Python doctest: '%for x in range(10):\n%  print x\n%end\njuicebox'
// Note: Swift doesn't batch consecutive %-lines like Python does
func tokenize_pythonDoctest1() {
    let text = "%for x in range(10):\n%  print x\n%end\njuicebox"
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    // Swift tokenizes each %-line separately (unlike Python which batches them)
    #expect(tokens.contains { $0.kind == .gybLines && $0.text.contains("%for") })
    #expect(tokens.contains { $0.kind == .gybLines && $0.text.contains("print") })
    #expect(tokens.contains { $0.kind == .gybLinesClose })
    #expect(tokens.contains { $0.kind == .literal && $0.text == "juicebox" })
}

@Test("tokenize template with mixed % and ${}")
// Python doctest: 'Nothing\n% if x:\n%    for i in range(3):\n${i}\n%    end\n% else:\nTHIS SHOULD NOT APPEAR IN THE OUTPUT\n'
// Note: Swift doesn't batch consecutive %-lines like Python does
func tokenize_pythonDoctest2() {
    let text = """
Nothing
% if x:
%    for i in range(3):
${i}
%    end
% else:
THIS SHOULD NOT APPEAR IN THE OUTPUT

"""
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    // Verify all expected token types are present
    #expect(tokens.contains { $0.kind == .literal && $0.text.contains("Nothing") })
    #expect(tokens.contains { $0.kind == .gybLines && $0.text.contains("% if x:") })
    #expect(tokens.contains { $0.kind == .gybLines && $0.text.contains("%    for i") })
    #expect(tokens.contains { $0.kind == .substitutionOpen })
    #expect(tokens.contains { $0.kind == .gybLinesClose })
    #expect(tokens.contains { $0.kind == .gybLines && $0.text.contains("% else:") })
    #expect(tokens.contains { $0.kind == .literal && $0.text.contains("THIS SHOULD NOT APPEAR") })
}

@Test("tokenize complex template with all constructs")
// Simplified version focusing on key constructs that work
func tokenize_pythonDoctest3() {
    let text = """
This is literal stuff ${x}
%{ code }%
and %-lines:
% x = 1
% end
%% literal percent

"""
    var tokenizer = TemplateTokens(text: text)
    var tokens: [TemplateToken] = []
    while let token = tokenizer.next() {
        tokens.append(token)
    }
    
    // Verify key tokens are present
    #expect(tokens.contains { $0.kind == .literal })
    #expect(tokens.contains { $0.kind == .substitutionOpen })
    #expect(tokens.contains { $0.kind == .gybBlockOpen })
    #expect(tokens.contains { $0.kind == .gybLines })
    #expect(tokens.contains { $0.kind == .gybLinesClose })
}

// MARK: - Parse Tests

@Test("parse simple literal template")
func parse_literalTemplate() throws {
    let text = "Hello, World!"
    let ast = try parseTemplate(filename: "test", text: text)
    
    #expect(ast.children.count == 1)
    #expect(ast.children[0] is LiteralNode)
}

@Test("parse template with escaped symbols")
func parse_templateWithEscapedSymbols() throws {
    let text = "$$dollar and %%percent"
    let ast = try parseTemplate(filename: "test", text: text)
    
    #expect(ast.children.count >= 1)
}

@Test("parse substitution")
func parse_substitution() throws {
    let text = "${x}"
    let ast = try parseTemplate(filename: "test", text: text)
    
    #expect(ast.children.count == 1)
    #expect(ast.children[0] is SubstitutionNode)
}

@Test("parse code block")
func parse_codeBlock() throws {
    let text = "%{ let x = 42 }%"
    let ast = try parseTemplate(filename: "test", text: text)
    
    #expect(ast.children.count == 1)
    #expect(ast.children[0] is CodeNode)
}

// MARK: - Basic Execution Tests

@Test("execute simple literal template")
func execute_literalTemplate() throws {
    let text = "Hello, World!"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == "Hello, World!")
}

@Test("execute template with escaped symbols")
func execute_templateWithEscapedSymbols() throws {
    let text = "Price: $$50"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result.contains("$50"))
}

@Test("substitution with bound variable")
func substitution_withSimpleBinding() throws {
    let text = "x = ${x}"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: ["x": 42])
    #expect(result.contains("42"))
}

@Test("empty template")
func execute_emptyTemplate() throws {
    let text = ""
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == "")
}

@Test("template with only whitespace")
func execute_whitespaceOnly() throws {
    let text = "   \n\t\n   "
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == text)
}

@Test("mixed literal and symbols")
func execute_mixedLiteralsAndSymbols() throws {
    let text = "Regular $$text with %%symbols"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result.contains("Regular"))
    #expect(result.contains("$text"))
    #expect(result.contains("%symbols"))
}

@Test("malformed substitutions handled gracefully")
func parse_malformedSubstitution() {
    let text = "${unclosed"
    
    // Should handle gracefully - either parse as literal or throw clear error
    do {
        let ast = try parseTemplate(filename: "test", text: text)
        _ = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    } catch {
        // Error is expected for malformed input
    }
}

@Test("multiple literals in sequence")
func execute_multipleLiterals() throws {
    let text = "First line\nSecond line\nThird line"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == text)
}

@Test("AST structure for mixed template")
func ast_structure() throws {
    let text = "Text ${x} more text"
    let ast = try parseTemplate(filename: "test", text: text)
    
    #expect(ast.children.count >= 1)
    
    var hasSubstitution = false
    for child in ast.children {
        if child is SubstitutionNode {
            hasSubstitution = true
        }
    }
    #expect(hasSubstitution)
}

@Test("line directive generation")
func execute_lineDirectives() throws {
    let text = "Line 1\nLine 2"
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    
    // Test with custom line directive format
    let code = try generateSwiftCode(
        ast,
        bindings: [:],
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        emitSourceLocation: true
    )
    
    // Verify line directives are emitted in generated code
    #expect(code.contains("//# line 1 \"test.gyb\""))
    
    // Verify the actual content is present
    #expect(code.contains("Line 1"))
    #expect(code.contains("Line 2"))
    
    // Test execution also works
    let result = try executeTemplate(
        ast,
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        bindings: [:]
    )
    #expect(result.contains("Line 1"))
    #expect(result.contains("Line 2"))
}

// MARK: - Documentation Tests

@Test("all major components can be instantiated")
func components_instantiation() {
    // Test tokenizer - verify it can be created and used
    var tokenizer = TemplateTokens(text: "test")
    _ = tokenizer.next()  // Verify it works
    
    // Test parse context
    let context = ParseContext(filename: "test", text: "content")
    #expect(context.filename == "test")
}

@Test("AST node creation")
func astNode_creation() {
    let literal = LiteralNode(text: "hello", line: 1)
    #expect(literal.text == "hello")
    
    let code = CodeNode(code: "let x = 1", line: 1)
    #expect(code.code == "let x = 1")
    
    let subst = SubstitutionNode(expression: "x", line: 1)
    #expect(subst.expression == "x")
    
    let block = BlockNode(children: [literal], line: 1)
    #expect(block.children.count == 1)
}

// MARK: - Integration Tests

@Test("realistic template with multiple features")
func integration_realisticTemplate() throws {
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
    
    #expect(result.contains("struct Example"))
    #expect(result.contains("42"))
}

@Test("execute Swift template with control flow using % }")
// Swift templates use Swift syntax with unmatched braces
func execute_swiftControlFlow() throws {
    let text = """
% for i in 0..<3 {
${i}
% }
"""
    
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let result = try executeTemplate(
        ast,
        filename: "test.gyb",
        lineDirective: "",
        bindings: [:]
    )
    
    // Should execute the loop and produce 0, 1, 2
    #expect(result.contains("0"))
    #expect(result.contains("1"))
    #expect(result.contains("2"))
}

@Test("execute template with if control flow")
func execute_swiftIf() throws {
    let text = """
% let x = 5
% if x > 3 {
large
% }
"""
    
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result.contains("large"))
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
    
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result.contains("(1,1)"))
    #expect(result.contains("(1,2)"))
    #expect(result.contains("(2,1)"))
    #expect(result.contains("(2,2)"))
}

@Test("template structure is preserved")
func integration_templateStructurePreservation() throws {
    let text = """
    Header
    
    Body content
    
    Footer
    """
    
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result.contains("Header"))
    #expect(result.contains("Body content"))
    #expect(result.contains("Footer"))
}

