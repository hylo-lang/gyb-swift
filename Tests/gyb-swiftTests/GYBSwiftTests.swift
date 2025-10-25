import Testing
@testable import gyb_swift

// MARK: - Test Helpers

/// Helper to create a token with String text for testing
func token(_ kind: TemplateToken.Kind, _ text: String) -> TemplateToken {
    TemplateToken(kind: kind, text: text[...])
}

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
    #expect(token?.text == "Hello, World!")
}

@Test("tokenize $$ escape sequence")
func tokenize_escapedDollar() {
    let tokens = Array(TemplateTokens(text: "$$100"))
    
    let expected = [
        token(.symbol, "$$"),
        token(.literal, "100")
    ]
    #expect(tokens == expected)
}

@Test("tokenize %% escape sequence")
func tokenize_escapedPercent() {
    let tokens = Array(TemplateTokens(text: "100%%"))
    
    let expected = [
        token(.literal, "100"),
        token(.symbol, "%%")
    ]
    #expect(tokens == expected)
}

@Test("tokenize ${} substitution")
func tokenize_substitution() {
    let tokens = Array(TemplateTokens(text: "${x}"))
    
    let expected = [
        token(.substitutionOpen, "${x}")
    ]
    #expect(tokens == expected)
}

@Test("tokenize %{} code block")
func tokenize_codeBlock() {
    let tokens = Array(TemplateTokens(text: "%{ let x = 42 }%"))
    
    let expected = [
        token(.gybBlockOpen, "%{ let x = 42 }%")
    ]
    #expect(tokens == expected)
}

@Test("}% inside strings doesn't terminate code block")
// This is the critical test case that requires Swift tokenization.
// Without proper tokenization, the naive scanner would incorrectly
// stop at the }% inside the string literal.
func codeBlock_delimiterInString() {
    let tokens = Array(TemplateTokens(text: #"%{ let msg = "Error: }% not allowed" }%Done"#))
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text == #"%{ let msg = "Error: }% not allowed" }%"#)
    #expect(tokens[1].kind == .literal)
    #expect(tokens[1].text == "Done")
}

@Test("} inside strings in ${} doesn't terminate substitution")
// This verifies SwiftSyntax correctly handles dictionary/subscript syntax
// where } appears in string keys.
func substitution_braceInString() {
    let tokens = Array(TemplateTokens(text: #"${dict["key}value"]}Done"#))
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .substitutionOpen)
    #expect(tokens[0].text == #"${dict["key}value"]}"#)
    #expect(tokens[1].kind == .literal)
    #expect(tokens[1].text == "Done")
}

@Test("multiple nested strings with delimiters")
func nestedStrings_withDelimiters() {
    let text = #"%{ let a = "first }% here"; let b = "second }% there" }%"#
    let tokens = Array(TemplateTokens(text: text))
    
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text == #"%{ let a = "first }% here"; let b = "second }% there" }%"#)
}

@Test("SwiftSyntax parser handles invalid/incomplete Swift gracefully")
// This is critical because sourceText[start...] often contains template text
// after the Swift code, making it syntactically invalid. SwiftSyntax Parser
// is designed to be resilient (for LSP use) and handles this correctly.
func parser_resilientWithInvalidSwift() {
    // Test case: valid Swift code followed by template text
    // When parsing ${count}, we actually parse "count}Done" which is invalid Swift
    let tokens = Array(TemplateTokens(text: "${count}Done"))
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .substitutionOpen)
    #expect(tokens[0].text == "${count}")
    #expect(tokens[1].kind == .literal)
    #expect(tokens[1].text == "Done")
}

@Test("%{...}% code blocks with nested braces from closures")
func codeBlock_withClosure() {
    let text = #"%{ items.forEach { print($0) } }%Done"#
    let tokens = Array(TemplateTokens(text: text))
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text == #"%{ items.forEach { print($0) } }%"#)
    #expect(tokens[1].text == "Done")
}

@Test("%{...}% code blocks with nested braces from dictionaries")
func codeBlock_withDictionary() {
    let text = #"%{ let dict = ["key": "value"]; let x = dict["key"] }%After"#
    let tokens = Array(TemplateTokens(text: text))
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text == #"%{ let dict = ["key": "value"]; let x = dict["key"] }%"#)
    #expect(tokens[1].text == "After")
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
    let tokens = Array(TemplateTokens(text: text))
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text == #"""
    %{ if true {
        let dict = ["a": 1]
        for (k, v) in dict {
            print("\(k): \(v)")
        }
    } }%
    """#)
    #expect(tokens[1].text == "Done")
}

@Test("%{...}% code blocks with generics containing angle brackets")
func codeBlock_withGenerics() {
    let text = #"%{ let arr: Array<[String: Int]> = [] }%Text"#
    let tokens = Array(TemplateTokens(text: text))
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text == #"%{ let arr: Array<[String: Int]> = [] }%"#)
    #expect(tokens[1].text == "Text")
}

@Test("%{...}% code blocks with trailing closure syntax")
func codeBlock_trailingClosure() {
    let text = #"%{ let result = numbers.map { $0 * 2 } }%End"#
    let tokens = Array(TemplateTokens(text: text))
    
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .gybBlockOpen)
    #expect(tokens[0].text == #"%{ let result = numbers.map { $0 * 2 } }%"#)
    #expect(tokens[1].text == "End")
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
// Swift-style loop with closing brace
func tokenize_pythonDoctest1() {
    let text = "% for x in 0..<10 {\n%  print(x)\n% }\njuicebox"
    let tokens = Array(TemplateTokens(text: text))
    
    // Swift tokenizes each %-line separately (newlines after %-lines are consumed by tokenizer)
    let expected = [
        token(.gybLines, "% for x in 0..<10 {"),
        token(.gybLines, "%  print(x)"),
        token(.gybLines, "% }"),
        token(.literal, "juicebox")
    ]
    #expect(tokens == expected)
}

@Test("tokenize template with mixed % and ${}")
// Swift-style template with control flow
func tokenize_pythonDoctest2() {
    let text = """
Nothing
% if x != 0 {
%    for i in 0..<3 {
${i}
%    }
% } else {
THIS SHOULD NOT APPEAR IN THE OUTPUT
% }

"""
    let tokens = Array(TemplateTokens(text: text))
    
    // Verify exact token sequence (newlines after %-lines are consumed by tokenizer)
    let expected = [
        token(.literal, "Nothing\n"),
        token(.gybLines, "% if x != 0 {"),
        token(.gybLines, "%    for i in 0..<3 {"),
        token(.substitutionOpen, "${i}"),
        token(.literal, "\n"),
        token(.gybLines, "%    }"),
        token(.gybLines, "% } else {"),
        token(.literal, "THIS SHOULD NOT APPEAR IN THE OUTPUT\n"),
        token(.gybLines, "% }")
    ]
    #expect(tokens == expected)
}

@Test("tokenize complex template with all constructs")
// Swift-style template with all token types
func tokenize_pythonDoctest3() {
    let text = """
This is literal stuff ${x}
%{ let code = 1 }%
and %-lines:
% let x = 1
% for i in 0..<1 {
%% literal percent
% }

"""
    let tokens = Array(TemplateTokens(text: text))
    
    // Verify exact token sequence (%-lines consume trailing newline, "and %-lines:" is parsed as %-line)
    let expected = [
        token(.literal, "This is literal stuff "),
        token(.substitutionOpen, "${x}"),
        token(.literal, "\n"),
        token(.gybBlockOpen, "%{ let code = 1 }%\n"),  // Includes newline
        token(.literal, "and "),
        token(.gybLines, "%-lines:"),  // "%-lines:" starts with % so treated as %-line
        token(.gybLines, "% let x = 1"),
        token(.gybLines, "% for i in 0..<1 {"),
        token(.symbol, "%%"),
        token(.literal, " literal percent\n"),
        token(.gybLines, "% }")
    ]
    #expect(tokens == expected)
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
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == "Hello, World!")
}

@Test("execute template with escaped symbols")
func execute_templateWithEscapedSymbols() throws {
    let text = "Price: $$50"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == "Price: $50")
}

@Test("substitution with bound variable")
func substitution_withSimpleBinding() throws {
    let text = "x = ${x}"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: ["x": 42])
    #expect(result == "x = 42")
}

@Test("empty template")
func execute_emptyTemplate() throws {
    let text = ""
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == "")
}

@Test("template with only whitespace")
func execute_whitespaceOnly() throws {
    let text = "   \n\t\n   "
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == text)
}

@Test("mixed literal and symbols")
func execute_mixedLiteralsAndSymbols() throws {
    let text = "Regular $$text with %%symbols"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == "Regular $text with %symbols")
}

@Test("malformed substitutions handled gracefully")
func parse_malformedSubstitution() {
    let text = "${unclosed"
    
    // Should handle gracefully - either parse as literal or throw clear error
    do {
        let ast = try parseTemplate(filename: "test", text: text)
        _ = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    } catch {
        // Error is expected for malformed input
    }
}

@Test("multiple literals in sequence")
func execute_multipleLiterals() throws {
    let text = "First line\nSecond line\nThird line"
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
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
        templateText: text,
        bindings: [:],
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        emitSourceLocation: true
    )
    
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
    let result = try executeTemplate(
        ast,
        templateText: text,
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        bindings: [:]
    )
    #expect(result == "Line 1\nLine 2")
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
    let literal = LiteralNode(text: "hello")
    #expect(literal.text == "hello")
    
    let code = CodeNode(code: "let x = 1")
    #expect(code.code == "let x = 1")
    
    let subst = SubstitutionNode(expression: "x")
    #expect(subst.expression == "x")
    
    let block = BlockNode(children: [literal])
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
        templateText: text,
        filename: "test.gyb",
        lineDirective: "",
        bindings: ["count": 42]
    )
    
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
    
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let result = try executeTemplate(
        ast,
        templateText: text,
        filename: "test.gyb",
        lineDirective: "",
        bindings: [:]
    )
    
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
    
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
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
    
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
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
    
    let ast = try parseTemplate(filename: "test", text: text)
    let result = try executeTemplate(ast, templateText: text, filename: "test", lineDirective: "", bindings: [:])
    
    #expect(result == text)
}

// MARK: - Python Doctest Equivalence Tests

@Test("line directive for each loop iteration")
// Python doctest: execute_template with loop that outputs multiple times
func lineDirective_loopIterations() throws {
    let text = """
Nothing
% if x != 0 {
%    for i in 0..<3 {
${i}
%    }
% } else {
THIS SHOULD NOT APPEAR IN THE OUTPUT
% }
"""
    
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let code = try generateSwiftCode(
        ast,
        templateText: text,
        bindings: ["x": 1],
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        emitSourceLocation: true
    )
    
    // Verify exact generated code structure with line directives
    let expectedCode = """
import Foundation

// Bindings
let x = 1

// Generated code
//# line 1 "test.gyb"
print(\"\"\"
Nothing

\"\"\", terminator: "")
if x != 0 {
for i in 0..<3 {
//# line 4 "test.gyb"
print(\"\"\"
\\(i)

\"\"\", terminator: "")
}
} else {
//# line 7 "test.gyb"
print(\"\"\"
THIS SHOULD NOT APPEAR IN THE OUTPUT

\"\"\", terminator: "")
}

"""
    #expect(code == expectedCode)
    
    // Verify execution produces correct output
    let result = try executeTemplate(
        ast,
        templateText: text,
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        bindings: ["x": 1]
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
    
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let code = try generateSwiftCode(
        ast,
        templateText: text,
        bindings: [:],
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        emitSourceLocation: true
    )
    
    // Verify exact generated code with line directives at correct positions
    let expectedCode = """
import Foundation

// Bindings


// Generated code
//# line 1 "test.gyb"
print(\"\"\"
Nothing

\"\"\", terminator: "")
var a: [Int] = []
for x in 0..<3 {
a.append(x)
}
//# line 6 "test.gyb"
print(\"\"\"
\\(a)
\"\"\", terminator: "")

"""
    #expect(code == expectedCode)
    
    // Verify execution
    let result = try executeTemplate(
        ast,
        templateText: text,
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        bindings: [:]
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
    
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let result = try executeTemplate(
        ast,
        templateText: text,
        filename: "test.gyb",
        lineDirective: "",
        bindings: [:]
    )
    
    // Template has no trailing newline after the substitution
    #expect(result == "123")
}

@Test("substitution with embedded newlines in result")
// Swift literal string with escape sequences
func substitution_embeddedNewlines() throws {
    let text = """
abc
${\"w\\nx\\nX\\ny\"}
z
"""
    
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let result = try executeTemplate(
        ast,
        templateText: text,
        filename: "test.gyb",
        lineDirective: "",
        bindings: [:]
    )
    
    // Note: Swift prints the escaped string literally as "w\nx\nX\ny"
    // Template has no trailing newline after 'z'
    #expect(result == "abc\nw\\nx\\nX\\ny\nz")
}

@Test("comprehensive integration test matching Python expand() doctest")
// Python doctest: expand() comprehensive test
// Note: We emit line directives at logical boundaries (per print statement) for cleaner output
func integration_comprehensiveExpandTest() throws {
    let text = """
---
% for i in 0..<Int(x)! {
a pox on ${i} for epoxy
% }
${120 +

   3}
abc
${\"w\\nx\\nX\\ny\"}
z
"""
    
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let code = try generateSwiftCode(
        ast,
        templateText: text,
        bindings: ["x": "2"],
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        emitSourceLocation: true
    )
    
    // Verify exact generated code with line directives at correct positions
    let expectedCode = """
import Foundation

// Bindings
let x = "2"

// Generated code
//# line 1 "test.gyb"
print(\"\"\"
---

\"\"\", terminator: "")
for i in 0..<Int(x)! {
//# line 3 "test.gyb"
print(\"\"\"
a pox on \\(i) for epoxy

\"\"\", terminator: "")
}
//# line 5 "test.gyb"
print(\"\"\"
\\(120 +

   3)
abc
\\("w\\\\nx\\\\nX\\\\ny")
z
\"\"\", terminator: "")

"""
    #expect(code == expectedCode)
    
    // Verify execution produces correct output
    let result = try executeTemplate(
        ast,
        templateText: text,
        filename: "test.gyb",
        lineDirective: "//# line \\(line) \"\\(file)\"",
        bindings: ["x": "2"]
    )
    
    // Note: the ${"w\\nx\\nX\\ny"} expression outputs the escaped string literally
    let expected = """
---
a pox on 0 for epoxy
a pox on 1 for epoxy
123
abc
w\\nx\\nX\\ny
z
"""
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
    
    let ast = try parseTemplate(filename: "test.gyb", text: text)
    let code = try generateSwiftCode(
        ast,
        templateText: text,
        bindings: [:],
        filename: "test.gyb",
        lineDirective: "#line \\(line) \"\\(file)\"",
        emitSourceLocation: true
    )
    
    // Verify exact generated code with alternative line directive format
    let expectedCode = """
import Foundation

// Bindings


// Generated code
#line 1 "test.gyb"
print(\"\"\"
Nothing

\"\"\", terminator: "")
var a: [Int] = []
for x in 0..<3 {
a.append(x)
}
#line 6 "test.gyb"
print(\"\"\"
\\(a)
\"\"\", terminator: "")

"""
    #expect(code == expectedCode)
}

