import Algorithms
import Foundation

// MARK: - Code Generation

/// Generates Swift code from AST nodes.
struct CodeGenerator {
  /// Source template for location tracking.
  let sourceTemplate: Lines<String>
  /// Template filename for source location directives.
  let filename: String
  /// Line directive format for output with `\(file)` and `\(line)` placeholders, or empty to omit.
  let lineDirective: String
  /// Whether to emit line directives in the template output.
  let emitLineDirectives: Bool

  init(
    template: String,
    filename: String = "",
    lineDirective: String = "",
    emitLineDirectives: Bool = false
  ) {
    self.sourceTemplate = Lines(template)
    self.filename = filename
    self.lineDirective = lineDirective
    self.emitLineDirectives = emitLineDirectives
  }

  /// Returns the template body executing `nodes`, batching consecutive nodes of the same type.
  func generateBody(_ nodes: [ASTNode]) -> String {
    // Group consecutive nodes: output nodes together, code nodes together
    let chunks = nodes.chunked { prev, curr in
      (isOutputNode(prev) && isOutputNode(curr)) || (prev is CodeNode && curr is CodeNode)
    }

    let lines = chunks.map { chunk -> String in
      // Code nodes: emit with source location directive at the start
      if let firstCode = chunk.first as? CodeNode {
        let lineNumber = sourceTemplate.lineNumber(at: firstCode.sourcePosition)

        // Concatenate all code from consecutive code nodes
        let codeLines = chunk.compactMap { ($0 as? CodeNode)?.code }.map(String.init)

        return sourceLocationDirective(file: filename, line: lineNumber) + "\n"
          + codeLines.joined(separator: "\n")
      }

      // Output nodes are batched into print statements
      return printStatement(chunk)
    }

    return lines.joined(separator: "\n")
  }

  /// Returns a complete Swift program for `ast` with `bindings`.
  func generateCompleteProgram(_ ast: AST, bindings: [String: String] = [:]) -> String {
    // Generate bindings code
    let bindingsCode =
      bindings
      .map { "let \($0.key) = \(String(reflecting: $0.value))" }
      .joined(separator: "\n")

    // Generate template body
    let body = generateBody(ast)

    let code = """
      // Bindings
      \(bindingsCode)

      // Template body
      \(body)

      """

    // Fix any misplaced #sourceLocation directives
    return fixSourceLocationPlacement(code)
  }

  /// Returns the start position of `nodes`'s first element.
  private func positionOfFirst(_ nodes: AST.SubSequence) -> String.Index {
    let first = nodes.first!

    if let literal = first as? LiteralNode {
      return literal.text.startIndex
    } else if let substitution = first as? SubstitutionNode {
      return substitution.expression.startIndex
    }
    fatalError("Unexpected node type: \(type(of: first))")
  }

  /// Returns `nodes`'s text content as strings, with substitutions formatted as `\(expression)`.
  private func textContent(_ nodes: AST.SubSequence) -> [String] {
    return nodes.map { node in
      if let literal = node as? LiteralNode {
        return String(literal.text)
      } else if let substitution = node as? SubstitutionNode {
        return #"\(\#(substitution.expression))"#
      }
      fatalError("Unexpected node type: \(type(of: node))")
    }
  }

  private func sourceLocationDirective(file: String, line: Int) -> String {
    "#sourceLocation(file: \"\(file)\", line: \(line))"
  }

  /// Returns a Swift print statement outputting `nodes`'s combined text.
  ///
  /// Always includes a `#sourceLocation` directive in the generated Swift code for error reporting.
  /// Optionally prints line directives into the output when configured.
  private func printStatement(_ nodes: AST.SubSequence) -> String {
    let combined = textContent(nodes).joined()
    var swiftCode: [String] = []

    // Always emit #sourceLocation in the intermediate Swift code for error reporting
    let index = positionOfFirst(nodes)
    let lineNumber = sourceTemplate.lineNumber(at: index)
    swiftCode.append(sourceLocationDirective(file: filename, line: lineNumber))

    // Optionally print line directives into the output
    var output = combined
    if emitLineDirectives && !lineDirective.isEmpty {
      let outputDirective =
        lineDirective.substituting(file: filename, line: lineNumber)
      output = outputDirective + "\n" + output
    }

    // Separated in formatting to avoid confusing Emacs swift-mode
    // (https://github.com/swift-emacs/swift-mode/issues/200)
    func quotes(_ i: Int) -> String { String(repeating: "\"", count: i) }

    swiftCode.append(
      """
      print(\"""
      \(output.escapedForSwiftMultilineString())
      \""", terminator: "")
      """)

    return swiftCode.joined(separator: "\n")
  }

  /// Returns whether `node` represents template output.
  private func isOutputNode(_ node: ASTNode) -> Bool {
    return node is LiteralNode || node is SubstitutionNode
  }
}

extension String {
  /// Returns `template`'s `\(file)` and `\(line)` placeholders replaced by `filename` and `line`.
  fileprivate func substituting(file: String, line: Int) -> String {
    return
      self
      .replacingOccurrences(of: #"\(file)"#, with: file)
      .replacingOccurrences(of: #"\(line)"#, with: "\(line)")
  }

  /// Returns `self` escaped for embedding in Swift
  /// multiline string literals, but preserving `\(...)` interpolations.
  fileprivate func escapedForSwiftMultilineString() -> String {
    replacingOccurrences(of: #"\"#, with: #"\\"#)
      .replacingOccurrences(of: #"""""#, with: #"\"\"\""#)
      // Undo escaping for interpolations so \(expr) is undisturbed.
      .replacingOccurrences(of: #"\\("#, with: #"\("#)
  }
}
