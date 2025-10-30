import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - Token Types

/// Represents a token extracted from a template.
struct TemplateToken: Equatable {
  /// The type of token.
  enum Kind: Equatable {
    /// Literal text to output as-is.
    case literal
    /// A ${...} substitution expression.
    case substitutionOpen
    /// One or more %-lines of Swift code.
    case gybLines
    /// A %{...}% code block.
    case gybBlock
    /// An escaped symbol (%% or $$).
    case symbol
  }

  /// The token type.
  let kind: Kind
  /// The token's text in the original template, preserving position via `startIndex`.
  let text: Substring

  // Custom equality that compares text content, not indices
  static func == (lhs: TemplateToken, rhs: TemplateToken) -> Bool {
    return lhs.kind == rhs.kind && String(lhs.text) == String(rhs.text)
  }
}

// MARK: - Template Tokenization

/// Tokenizes template text into literal text, substitutions, code blocks, code lines, and symbols.
///
/// Note: The Python version uses a complex regex (tokenize_re). The Swift version uses
/// a character-by-character state machine which is more maintainable and handles Swift syntax correctly.
struct TemplateTokens: Sequence, IteratorProtocol {
  /// The unconsumed portion of the template text.
  private var remainingText: Substring

  init(text: String) {
    self.remainingText = text[...]
  }

  /// Returns the next token, or nil when exhausted.
  mutating func next() -> TemplateToken? {
    guard let char = remainingText.first else { return nil }

    // Check for special sequences
    if char == "$" {
      return handleDollar()
    } else if char == "%" {
      return handlePercent()
    } else {
      return handleLiteral()
    }
  }

  /// Handles $ character (substitution or escaped $).
  private mutating func handleDollar() -> TemplateToken? {
    let rest = remainingText.dropFirst()
    guard let nextChar = rest.first else {
      let token = TemplateToken(kind: .literal, text: remainingText.prefix(1))
      remainingText = rest
      return token
    }

    if nextChar == "$" {
      // $$ -> literal $
      let token = TemplateToken(kind: .symbol, text: remainingText.prefix(2))
      remainingText = rest.dropFirst()
      return token
    } else if nextChar == "{" {
      // ${...} -> substitution
      return handleSubstitution()
    } else {
      // Just a literal $
      let token = TemplateToken(kind: .literal, text: remainingText.prefix(1))
      remainingText = rest
      return token
    }
  }

  /// Handles % character (code lines, blocks, or escaped %).
  private mutating func handlePercent() -> TemplateToken? {
    let rest = remainingText.dropFirst()
    guard let nextChar = rest.first else {
      let token = TemplateToken(kind: .literal, text: remainingText.prefix(1))
      remainingText = rest
      return token
    }

    if nextChar == "%" {
      // %% -> literal %
      let token = TemplateToken(kind: .symbol, text: remainingText.prefix(2))
      remainingText = rest.dropFirst()
      return token
    } else if nextChar == "{" {
      // %{...}% -> code block
      return handleCodeBlock()
    } else if nextChar == " " || nextChar == "\t" || nextChar.isNewline {
      // Check if it's %end
      return handleCodeLine()
    } else {
      // % at start of line followed by code
      return handleCodeLine()
    }
  }

  /// Handles ${...} substitution using Swift tokenization for `}` in strings.
  private mutating func handleSubstitution() -> TemplateToken? {
    // Skip ${
    let codePart = remainingText.dropFirst(2)

    // Use Swift tokenizer to find the real closing }
    let closeIndex = codePart.indexOfFirstSwiftUnmatchedCloseCurly()

    if closeIndex < codePart.endIndex {
      // Include ${ + code + }
      let endIndex = remainingText.index(after: closeIndex)
      let tokenText = remainingText[..<endIndex]
      remainingText = remainingText[endIndex...]
      return TemplateToken(kind: .substitutionOpen, text: tokenText)
    }

    // Unclosed substitution - treat as literal
    let token = TemplateToken(kind: .literal, text: remainingText.prefix(1))
    remainingText = remainingText.dropFirst()
    return token
  }

  /// Handles %{...}% code block using Swift tokenization for `}%` in strings.
  private mutating func handleCodeBlock() -> TemplateToken? {
    // Skip %{
    let codePart = remainingText.dropFirst(2)

    // Use Swift tokenizer to find the real closing }
    let closeIndex = codePart.indexOfFirstSwiftUnmatchedCloseCurly()

    if closeIndex < codePart.endIndex {
      let afterClose = codePart.index(after: closeIndex)
      if afterClose < codePart.endIndex && codePart[afterClose] == "%" {
        // Include %{ + code + }%
        var endIndex = codePart.index(after: afterClose)

        // Skip trailing newline if present
        if endIndex < remainingText.endIndex && remainingText[endIndex].isNewline {
          endIndex = remainingText.index(after: endIndex)
        }

        let tokenText = remainingText[..<endIndex]
        remainingText = remainingText[endIndex...]
        return TemplateToken(kind: .gybBlock, text: tokenText)
      }
    }

    // Unclosed block - treat as literal
    let token = TemplateToken(kind: .literal, text: remainingText.prefix(1))
    remainingText = remainingText.dropFirst()
    return token
  }

  /// Handles % code lines.
  /// Swift is brace-delimited, so we treat all %-lines uniformly as code.
  /// No special handling for % } or %end - just emit the code as-is.
  private mutating func handleCodeLine() -> TemplateToken? {
    // Read entire line as code
    let line = remainingText.prefix(while: { !$0.isNewline })
    let afterLine = remainingText.dropFirst(line.count)
    remainingText = afterLine.isEmpty ? afterLine : afterLine.dropFirst()

    return TemplateToken(kind: .gybLines, text: line)
  }

  /// Handles literal text.
  private mutating func handleLiteral() -> TemplateToken? {
    // Read until we hit $ or %
    let literal = remainingText.prefix(while: { $0 != "$" && $0 != "%" })

    // If we got nothing, take one character (shouldn't happen but be safe)
    let tokenText = literal.isEmpty ? remainingText.prefix(1) : literal
    remainingText = remainingText.dropFirst(tokenText.count)

    return TemplateToken(kind: .literal, text: tokenText)
  }
}

// MARK: - Swift Tokenization

extension StringProtocol {
  /// The index of the first unmatched `}` when parsed as Swift code, or `endIndex` if none exists.
  ///
  /// Uses SwiftSyntax to properly handle braces within strings and comments.
  func indexOfFirstSwiftUnmatchedCloseCurly() -> String.Index {
    // Parse to get tokens, which automatically handles braces within strings and comments.
    let parsed = Parser.parse(source: String(self))

    var nesting = 0
    for token in parsed.tokens(viewMode: .sourceAccurate) {
      if token.tokenKind == .leftBrace {
        nesting += 1
      } else if token.tokenKind == .rightBrace {
        nesting -= 1
        if nesting < 0 {
          return indexFromUTF8Offset(token.positionAfterSkippingLeadingTrivia.utf8Offset)
        }
      }
    }

    return endIndex
  }

  /// Converts a UTF-8 byte offset to a `String.Index`.
  func indexFromUTF8Offset(_ utf8Offset: Int) -> String.Index {
    let utf8Index = utf8.index(utf8.startIndex, offsetBy: utf8Offset)
    return String.Index(utf8Index, within: self) ?? endIndex
  }
}
