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
    let text: Substring
    // Note: text.startIndex gives position in original template
}

// MARK: - Template Tokenization

/// Tokenizes template text into literal text, substitutions, code blocks, code lines, and symbols.
// Note: The Python version uses a complex regex (tokenize_re). The Swift version uses
// a character-by-character state machine which is more maintainable and handles Swift syntax correctly.
struct TemplateTokens {
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
        let codePart = String(remainingText.dropFirst(2))
        
        // Use Swift tokenizer to find the real closing }
        let closeIndex = tokenizeSwiftToUnmatchedCloseCurly(
            sourceText: codePart,
            start: codePart.startIndex
        )
        
        if closeIndex < codePart.endIndex {
            // Include ${ + code + }
            let consumeCount = 2 + codePart.distance(from: codePart.startIndex, to: closeIndex) + 1
            let tokenText = remainingText.prefix(consumeCount)
            remainingText = remainingText.dropFirst(consumeCount)
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
        let codePart = String(remainingText.dropFirst(2))
        
        // Use Swift tokenizer to find the real closing }
        let closeIndex = tokenizeSwiftToUnmatchedCloseCurly(
            sourceText: codePart,
            start: codePart.startIndex
        )
        
        if closeIndex < codePart.endIndex {
            let afterClose = codePart.index(after: closeIndex)
            if afterClose < codePart.endIndex && codePart[afterClose] == "%" {
                // Include %{ + code + }%
                var consumeCount = 2 + codePart.distance(from: codePart.startIndex, to: codePart.index(after: afterClose))
                
                // Skip trailing newline if present
                let afterToken = remainingText.dropFirst(consumeCount)
                if afterToken.first?.isNewline == true {
                    consumeCount += 1
                }
                
                let tokenText = remainingText.prefix(consumeCount)
                remainingText = remainingText.dropFirst(consumeCount)
                return TemplateToken(kind: .gybBlockOpen, text: tokenText)
            }
        }
        
        // Unclosed block - treat as literal
        let token = TemplateToken(kind: .literal, text: remainingText.prefix(1))
        remainingText = remainingText.dropFirst()
        return token
    }
    
    /// Handles % code lines.
    private mutating func handleCodeLine() -> TemplateToken? {
        // Skip % and optional whitespace to check what follows
        var afterPercent = remainingText.dropFirst()
        while let char = afterPercent.first, char == " " || char == "\t" {
            afterPercent = afterPercent.dropFirst()
        }
        
        // Check for % } (closing brace line - Swift's equivalent to Python's %end)
        if afterPercent.first == "}" {
            let afterBrace = afterPercent.dropFirst()
            if afterBrace.first?.isWhitespace == true || afterBrace.first == "#" || afterBrace.isEmpty {
                // Consume up to and including the newline
                let line = remainingText.prefix(while: { !$0.isNewline })
                let afterLine = remainingText.dropFirst(line.count)
                remainingText = afterLine.isEmpty ? afterLine : afterLine.dropFirst()
                return TemplateToken(kind: .gybLinesClose, text: "% }")
            }
        }
        
        // Also support %end for compatibility with Python templates
        if afterPercent.starts(with: "end") {
            let afterEnd = afterPercent.dropFirst(3)
            if afterEnd.first?.isWhitespace == true || afterEnd.first == "#" || afterEnd.isEmpty {
                let line = remainingText.prefix(while: { !$0.isNewline })
                let afterLine = remainingText.dropFirst(line.count)
                remainingText = afterLine.isEmpty ? afterLine : afterLine.dropFirst()
                return TemplateToken(kind: .gybLinesClose, text: "%end")
            }
        }
        
        // Regular code line - read to end of line
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

/// Returns the index of the first unmatched `}` in Swift code starting at `start`,
/// or `sourceText.endIndex` if none exists, using SwiftSyntax to ignore braces in strings and comments.
func tokenizeSwiftToUnmatchedCloseCurly(
    sourceText: String,
    start: String.Index
) -> String.Index {
    // Keep as Substring to preserve index relationship with sourceText
    let substringSlice = sourceText[start...]
    
    // Parse the Swift code (SwiftSyntax requires a String)
    let source = Parser.parse(source: String(substringSlice))
    
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
                    // Found unmatched closing brace
                    // Use positionAfterSkippingLeadingTrivia which gives the actual token position
                    closeBraceOffset = token.positionAfterSkippingLeadingTrivia.utf8Offset
                    return .skipChildren
                }
            }
            return .visitChildren
        }
    }
    
    let visitor = BraceVisitor(viewMode: .all)
    visitor.walk(source)
    
    if let utf8Offset = visitor.closeBraceOffset {
        // Convert UTF-8 offset to String.Index efficiently using the Substring's utf8 view
        // The Substring shares indices with the original String, so this index is already valid!
        let utf8Index = substringSlice.utf8.index(substringSlice.utf8.startIndex, offsetBy: utf8Offset)
        if let stringIndex = String.Index(utf8Index, within: substringSlice) {
            return stringIndex  // Already a valid index into sourceText!
        }
    }
    
    return sourceText.endIndex
}
