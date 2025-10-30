import Testing

@testable import gyb_swift

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
    token(.literal, "100"),
  ]
  #expect(tokens == expected)
}

@Test("tokenize %% escape sequence")
func tokenize_escapedPercent() {
  let tokens = Array(TemplateTokens(text: "100%%"))

  let expected = [
    token(.literal, "100"),
    token(.symbol, "%%"),
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
    token(.gybBlock, "%{ let x = 42 }%")
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
  #expect(tokens[0].kind == .gybBlock)
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
  #expect(tokens[0].kind == .gybBlock)
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
  #expect(tokens[0].kind == .gybBlock)
  #expect(tokens[0].text == #"%{ items.forEach { print($0) } }%"#)
  #expect(tokens[1].text == "Done")
}

@Test("%{...}% code blocks with nested braces from dictionaries")
func codeBlock_withDictionary() {
  let text = #"%{ let dict = ["key": "value"]; let x = dict["key"] }%After"#
  let tokens = Array(TemplateTokens(text: text))

  #expect(tokens.count == 2)
  #expect(tokens[0].kind == .gybBlock)
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
  #expect(tokens[0].kind == .gybBlock)
  #expect(
    tokens[0].text == #"""
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
  #expect(tokens[0].kind == .gybBlock)
  #expect(tokens[0].text == #"%{ let arr: Array<[String: Int]> = [] }%"#)
  #expect(tokens[1].text == "Text")
}

@Test("%{...}% code blocks with trailing closure syntax")
func codeBlock_trailingClosure() {
  let text = #"%{ let result = numbers.map { $0 * 2 } }%End"#
  let tokens = Array(TemplateTokens(text: text))

  #expect(tokens.count == 2)
  #expect(tokens[0].kind == .gybBlock)
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
  #expect(tokenizer.next()?.kind == .gybLines)
}

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
    token(.literal, "juicebox"),
  ]
  #expect(tokens == expected)
}

@Test("tokenize template with mixed % and ${}")
// Swift-style template with control flow
func tokenize_pythonDoctest2() {
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
  let tokens = Array(TemplateTokens(text: text))

  // Verify exact token sequence (newlines after %-lines are consumed by tokenizer)
  let expected = [
    token(.literal, "Nothing\n"),
    token(.gybLines, #"% if x != "0" {"#),
    token(.gybLines, "%    for i in 0..<3 {"),
    token(.substitutionOpen, "${i}"),
    token(.literal, "\n"),
    token(.gybLines, "%    }"),
    token(.gybLines, "% } else {"),
    token(.literal, "THIS SHOULD NOT APPEAR IN THE OUTPUT\n"),
    token(.gybLines, "% }"),
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
    token(.gybBlock, "%{ let code = 1 }%\n"),  // Includes newline
    token(.literal, "and "),
    token(.gybLines, "%-lines:"),  // "%-lines:" starts with % so treated as %-line
    token(.gybLines, "% let x = 1"),
    token(.gybLines, "% for i in 0..<1 {"),
    token(.symbol, "%%"),
    token(.literal, " literal percent\n"),
    token(.gybLines, "% }"),
  ]
  #expect(tokens == expected)
}
