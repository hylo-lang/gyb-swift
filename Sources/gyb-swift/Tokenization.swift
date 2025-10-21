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

/// Tokenizes template text into literal text, substitutions, code blocks, code lines, and symbols.
// Note: The Python version uses a complex regex (tokenize_re). The Swift version uses
// a character-by-character state machine which is more maintainable and handles Swift syntax correctly.
struct TemplateTokens {
    private let text: String
    private var position: String.Index
    
    init(text: String) {
        self.text = text
        self.position = text.startIndex
    }
    
    /// Returns the next token, or nil when exhausted.
    mutating func next() -> TemplateToken? {
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
    private mutating func handleDollar(startPos: String.Index) -> TemplateToken? {
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
    private mutating func handlePercent(startPos: String.Index) -> TemplateToken? {
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
    
    /// Handles ${...} substitution using Swift tokenization for `}` in strings.
    private mutating func handleSubstitution(startPos: String.Index) -> TemplateToken? {
        // Skip ${
        let codeStart = text.index(position, offsetBy: 2)
        
        // Use Swift tokenizer to find the real closing }
        // This handles strings, comments, and nested braces correctly
        let closeIndex = tokenizeSwiftToUnmatchedCloseCurly(
            sourceText: text,
            start: codeStart
        )
        
        if closeIndex < text.endIndex {
            position = text.index(after: closeIndex)
            let tokenText = String(text[startPos..<position])
            return TemplateToken(kind: .substitutionOpen, text: tokenText, startIndex: startPos)
        }
        
        // Unclosed substitution - treat as literal
        position = text.index(after: startPos)
        return TemplateToken(kind: .literal, text: "$", startIndex: startPos)
    }
    
    /// Handles %{...}% code block using Swift tokenization for `}%` in strings.
    private mutating func handleCodeBlock(startPos: String.Index) -> TemplateToken? {
        // Skip %{
        let codeStart = text.index(position, offsetBy: 2)
        
        // Use Swift tokenizer to find the real closing }
        let closeIndex = tokenizeSwiftToUnmatchedCloseCurly(
            sourceText: text,
            start: codeStart
        )
        
        if closeIndex < text.endIndex {
            // Check if this is followed by %
            let afterClose = text.index(after: closeIndex)
            if afterClose < text.endIndex && text[afterClose] == "%" {
                position = text.index(after: afterClose)
                // Skip trailing newline if present
                if position < text.endIndex && text[position].isNewline {
                    position = text.index(after: position)
                }
                let tokenText = String(text[startPos..<position])
                return TemplateToken(kind: .gybBlockOpen, text: tokenText, startIndex: startPos)
            }
        }
        
        // Unclosed block - treat as literal
        position = text.index(after: startPos)
        return TemplateToken(kind: .literal, text: "%", startIndex: startPos)
    }
    
    /// Handles % code lines.
    private mutating func handleCodeLine(startPos: String.Index) -> TemplateToken? {
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
        
        // Skip optional whitespace after %
        while position < text.endIndex && (text[position] == " " || text[position] == "\t") {
            position = text.index(after: position)
        }
        
        // Check for % } (closing brace line - Swift's equivalent to Python's %end)
        let remaining = String(text[position...])
        if remaining.hasPrefix("}") {
            let endPos = text.index(after: position)
            // Check it's followed by whitespace, comment, or end of line
            if endPos >= text.endIndex || text[endPos].isWhitespace || text[endPos] == "#" || text[endPos].isNewline {
                // Find end of line
                while position < text.endIndex && !text[position].isNewline {
                    position = text.index(after: position)
                }
                if position < text.endIndex {
                    position = text.index(after: position)
                }
                return TemplateToken(kind: .gybLinesClose, text: "% }", startIndex: startPos)
            }
        }
        
        // Also support %end for compatibility with Python templates
        if remaining.hasPrefix("end") {
            let endPos = text.index(position, offsetBy: 3)
            if endPos >= text.endIndex || text[endPos].isWhitespace || text[endPos] == "#" {
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
    private mutating func handleLiteral(startPos: String.Index) -> TemplateToken? {
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

/// Returns the index of the first unmatched `}` in Swift code starting at `start`,
/// or `sourceText.endIndex` if none exists, using SwiftSyntax to ignore braces in strings and comments.
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
        var closeBraceOffset: Int?
        
        override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
            // If we already found the close brace, stop walking
            if closeBraceOffset != nil {
                return .skipChildren
            }
            
            if token.tokenKind == .leftBrace {
                nesting += 1
            } else if token.tokenKind == .rightBrace {
                nesting -= 1
                if nesting < 0 {
                    // Found unmatched closing brace - record offset in substring
                    closeBraceOffset = token.position.utf8Offset
                    return .skipChildren
                }
            }
            return .visitChildren
        }
    }
    
    let visitor = BraceVisitor(viewMode: .all)
    visitor.walk(source)
    
    if let utf8Offset = visitor.closeBraceOffset {
        // Convert UTF8 offset to character offset in substring
        // Count characters up to the UTF8 offset
        var charCount = 0
        var currentUTF8Offset = 0
        
        for char in substring {
            if currentUTF8Offset >= utf8Offset {
                break
            }
            currentUTF8Offset += char.utf8.count
            charCount += 1
        }
        
        // Apply character offset from start in original text
        if let absoluteIndex = sourceText.index(start, offsetBy: charCount, limitedBy: sourceText.endIndex) {
            return absoluteIndex
        }
    }
    
    return sourceText.endIndex
}
