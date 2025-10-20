import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - Token Types

/// Represents a token extracted from a template.
struct TemplateToken {
    /// The type of token.
    enum Kind {
        case literal
        case substitutionOpen  // ${
        case gybLines          // %-lines
        case gybLinesClose     // %end
        case gybBlockOpen      // %{
        case gybBlockClose     // }%
        case symbol            // %% or $$
    }
    
    let kind: Kind
    let text: String
    let startIndex: String.Index
}

// MARK: - Template Tokenization

/// Tokenizes template text into a sequence of tokens.
///
/// Recognizes literal text, substitutions, code blocks, code lines, and symbols.
class TemplateTokenizer {
    private let text: String
    private var position: String.Index
    
    /// Creates a tokenizer for template text.
    ///
    /// - Parameter text: The template to tokenize.
    init(text: String) {
        self.text = text
        self.position = text.startIndex
    }
    
    /// Returns the next token.
    ///
    /// - Returns: The next token, or nil if at end of text.
    func next() -> TemplateToken? {
        guard position < text.endIndex else { return nil }
        
        let startPos = position
        let char = text[position]
        
        // Check for special sequences
        if char == "$" {
            return handleDollar(startPos: startPos)
        } else if char == "%" {
            return handlePercent(startPos: startPos)
        } else {
            return handleLiteral(startPos: startPos)
        }
    }
    
    /// Handles $ character (substitution or escaped $).
    private func handleDollar(startPos: String.Index) -> TemplateToken? {
        let nextPos = text.index(after: position)
        guard nextPos < text.endIndex else {
            position = text.endIndex
            return TemplateToken(kind: .literal, text: "$", startIndex: startPos)
        }
        
        let nextChar = text[nextPos]
        
        if nextChar == "$" {
            // $$ -> literal $
            position = text.index(after: nextPos)
            return TemplateToken(kind: .symbol, text: "$$", startIndex: startPos)
        } else if nextChar == "{" {
            // ${...} -> substitution
            return handleSubstitution(startPos: startPos)
        } else {
            // Just a literal $
            position = nextPos
            return TemplateToken(kind: .literal, text: "$", startIndex: startPos)
        }
    }
    
    /// Handles % character (code lines, blocks, or escaped %).
    private func handlePercent(startPos: String.Index) -> TemplateToken? {
        let nextPos = text.index(after: position)
        guard nextPos < text.endIndex else {
            position = text.endIndex
            return TemplateToken(kind: .literal, text: "%", startIndex: startPos)
        }
        
        let nextChar = text[nextPos]
        
        if nextChar == "%" {
            // %% -> literal %
            position = text.index(after: nextPos)
            return TemplateToken(kind: .symbol, text: "%%", startIndex: startPos)
        } else if nextChar == "{" {
            // %{...}% -> code block
            return handleCodeBlock(startPos: startPos)
        } else if nextChar == " " || nextChar == "\t" || nextChar.isNewline {
            // Check if it's %end
            return handleCodeLine(startPos: startPos)
        } else {
            // % at start of line followed by code
            return handleCodeLine(startPos: startPos)
        }
    }
    
    /// Handles ${...} substitution.
    private func handleSubstitution(startPos: String.Index) -> TemplateToken? {
        // Skip ${
        position = text.index(position, offsetBy: 2)
        
        // Find matching }
        var depth = 1
        while position < text.endIndex {
            let char = text[position]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    position = text.index(after: position)
                    let tokenText = String(text[startPos..<position])
                    return TemplateToken(kind: .substitutionOpen, text: tokenText, startIndex: startPos)
                }
            }
            position = text.index(after: position)
        }
        
        // Unclosed substitution - treat as literal
        position = text.index(after: startPos)
        return TemplateToken(kind: .literal, text: "$", startIndex: startPos)
    }
    
    /// Handles %{...}% code block.
    private func handleCodeBlock(startPos: String.Index) -> TemplateToken? {
        // Skip %{
        position = text.index(position, offsetBy: 2)
        
        // Find }%
        while position < text.endIndex {
            let char = text[position]
            if char == "}" {
                let nextPos = text.index(after: position)
                if nextPos < text.endIndex && text[nextPos] == "%" {
                    // Found }%
                    let tokenText = String(text[startPos...nextPos])
                    position = text.index(after: nextPos)
                    // Skip trailing newline if present
                    if position < text.endIndex && text[position].isNewline {
                        position = text.index(after: position)
                    }
                    return TemplateToken(kind: .gybBlockOpen, text: tokenText, startIndex: startPos)
                }
            }
            position = text.index(after: position)
        }
        
        // Unclosed block
        position = text.index(after: startPos)
        return TemplateToken(kind: .literal, text: "%", startIndex: startPos)
    }
    
    /// Handles % code lines.
    private func handleCodeLine(startPos: String.Index) -> TemplateToken? {
        // Skip initial whitespace at start of line
        var lineStart = startPos
        while lineStart > text.startIndex {
            let prev = text.index(before: lineStart)
            let char = text[prev]
            if char.isNewline {
                break
            }
            if !char.isWhitespace {
                // Not at start of line with only whitespace
                position = text.index(after: startPos)
                return TemplateToken(kind: .literal, text: "%", startIndex: startPos)
            }
            lineStart = prev
        }
        
        // Skip %
        position = text.index(after: position)
        
        // Skip optional space after %
        if position < text.endIndex && text[position] == " " {
            position = text.index(after: position)
        }
        
        // Check for %end
        let remaining = String(text[position...])
        if remaining.hasPrefix("end") {
            let endPos = text.index(position, offsetBy: 3)
            // Check it's followed by whitespace or end
            if endPos >= text.endIndex || text[endPos].isWhitespace || text[endPos] == "#" {
                // Find end of line
                while position < text.endIndex && !text[position].isNewline {
                    position = text.index(after: position)
                }
                if position < text.endIndex {
                    position = text.index(after: position)
                }
                return TemplateToken(kind: .gybLinesClose, text: "%end", startIndex: startPos)
            }
        }
        
        // Regular code line - read to end of line
        while position < text.endIndex && !text[position].isNewline {
            position = text.index(after: position)
        }
        
        let tokenText = String(text[lineStart..<position])
        
        if position < text.endIndex {
            position = text.index(after: position)
        }
        
        return TemplateToken(kind: .gybLines, text: tokenText, startIndex: startPos)
    }
    
    /// Handles literal text.
    private func handleLiteral(startPos: String.Index) -> TemplateToken? {
        var endPos = position
        
        // Read until we hit $ or %
        while endPos < text.endIndex {
            let char = text[endPos]
            if char == "$" || char == "%" {
                break
            }
            endPos = text.index(after: endPos)
        }
        
        if endPos == position {
            // Single character
            endPos = text.index(after: position)
        }
        
        let tokenText = String(text[position..<endPos])
        position = endPos
        
        return TemplateToken(kind: .literal, text: tokenText, startIndex: startPos)
    }
}

// MARK: - Swift Tokenization

/// Tokenizes Swift code to find the matching close curly brace.
///
/// Uses SwiftSyntax to parse Swift code and track brace nesting.
///
/// - Parameters:
///   - sourceText: The text containing Swift code.
///   - start: The index where tokenization begins.
/// - Returns: Index of the unmatched close brace or end of text.
func tokenizeSwiftToUnmatchedCloseCurly(
    sourceText: String,
    start: String.Index
) -> String.Index {
    let substring = String(sourceText[start...])
    
    // Parse the Swift code
    let source = Parser.parse(source: substring)
    
    // Walk the syntax tree looking for braces
    class BraceVisitor: SyntaxVisitor {
        var nesting = 0
        var closeBracePosition: AbsolutePosition?
        
        override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
            if token.tokenKind == .leftBrace {
                nesting += 1
            } else if token.tokenKind == .rightBrace {
                nesting -= 1
                if nesting < 0 {
                    closeBracePosition = token.position
                    return .skipChildren
                }
            }
            return .visitChildren
        }
    }
    
    let visitor = BraceVisitor(viewMode: .all)
    visitor.walk(source)
    
    if let pos = visitor.closeBracePosition {
        // Convert UTF8 offset to String.Index
        let utf8Offset = pos.utf8Offset
        if let index = sourceText.utf8.index(
            sourceText.utf8.startIndex,
            offsetBy: utf8Offset,
            limitedBy: sourceText.utf8.endIndex
        ) {
            return String.Index(index, within: sourceText) ?? sourceText.endIndex
        }
    }
    
    return sourceText.endIndex
}
