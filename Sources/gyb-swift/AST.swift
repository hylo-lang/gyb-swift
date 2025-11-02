import Foundation

// MARK: - AST Node Protocol

/// A node in the template abstract syntax tree.
protocol ASTNode: CustomStringConvertible {}

// MARK: - Literal Node

/// Literal text from the template.
struct LiteralNode: ASTNode {
  /// The literal text content.
  let text: Substring

  var description: String {
    "Literal: \(text.prefix(20))\(text.dropFirst(20).isEmpty ? "" : "...")"
  }
}

// MARK: - Code Node

/// Swift code to be executed (from %-lines or %{...}% blocks).
struct CodeNode: ASTNode {
  /// The Swift code content.
  let code: Substring
  /// Source position in the original template for error reporting.
  let sourcePosition: String.Index

  var description: String {
    "Code: {\(code.prefix(30))\(code.dropFirst(30).isEmpty ? "" : "...")}"
  }
}

// MARK: - Substitution Node

/// A ${...} expression whose contents are evaluated as Swift,
/// converted to text, and inserted into the output.
struct SubstitutionNode: ASTNode {
  /// The Swift expression to evaluate.
  let expression: Substring

  var description: String {
    "Substitution: ${\(expression)}"
  }
}

// MARK: - AST

/// A parsed template represented as a sequence of top-level AST nodes.
typealias AST = [ASTNode]

extension AST {
  /// Creates an AST by parsing `template` from `filename`.
  init(filename: String, template: String) throws {
    var parser = Parser(filename: filename, text: template)
    self = try parser.parse()
  }
}

// MARK: - Helper Extensions

extension StringProtocol {
  /// The code content from a gyb block, with delimiters and optional trailing newline removed.
  ///
  /// - Precondition: `self` starts with `%{` and ends with `}%` or `}%\n`.
  var codeBlockContent: SubSequence {
    precondition(hasPrefix("%{"), "Expected %{ prefix")
    precondition(
      hasSuffix("}%") || hasSuffix("}%\n"),
      "Expected }% suffix with optional newline")
    let suffixLength = last?.isNewline == true ? 3 : 2  // }%\n or }%
    return dropFirst(2).dropLast(suffixLength)
  }
}

// MARK: - Parser

/// Parses template text into an AST.
struct Parser {
  /// Template source filename for error reporting.
  let filename: String
  /// The complete template being parsed.
  let template: String

  init(filename: String, text: String) {
    self.filename = filename
    self.template = text
  }

  /// Returns AST nodes parsed from the template.
  /// Simply converts each token to a node - no nesting logic.
  mutating func parse() throws -> AST {
    return TemplateTokens(text: template).map { token in
      switch token.kind {
      case .literal:
        return LiteralNode(text: token.text)

      case .substitutionOpen:
        // Extract expression between ${ and }
        return SubstitutionNode(expression: token.text.dropFirst(2).dropLast())

      case .gybLines:
        // Extract code from %-lines
        return CodeNode(
          code: extractCodeFromLines(token.text), sourcePosition: token.text.startIndex)

      case .gybBlock:
        // Extract code between %{ and }%
        return CodeNode(
          code: token.text.codeBlockContent,
          sourcePosition: token.text.startIndex)

      case .symbol:
        // %% or $$ becomes single % or $
        return LiteralNode(text: token.text.prefix(1))
      }
    }
  }

  /// Returns executable code from %-lines with leading % and indentation removed.
  private func extractCodeFromLines(_ text: Substring) -> Substring {
    text.split(omittingEmptySubsequences: false) { $0.isNewline }
      .map { line in
        line.drop { $0 != "%" }.dropFirst().drop(while: \.isWhitespace)
      }
      .joined(separator: "\n")[...]
  }
}
