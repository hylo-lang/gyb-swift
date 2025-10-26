import Foundation
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax

/// Fixes misplaced `#sourceLocation` directives in generated Swift code.
///
/// Uses SwiftParser to detect syntax errors caused by misplaced directives.
/// Moves problematic directives down line-by-line until they become legal or are discarded.
func fixSourceLocationPlacement(_ code: String) -> String {
    var currentCode = code

    // Keep trying to fix until no more fixes are needed or we've tried enough times
    for _ in 0..<100 {  // Arbitrary limit to prevent infinite loops
        let parseResult = parseAndFindProblematicDirectives(currentCode)

        if parseResult.problematicDirectives.isEmpty {
            break
        }

        // Fix the first problematic directive we find
        if let fixed = fixFirstProblematicDirective(currentCode, parseResult.problematicDirectives)
        {
            currentCode = fixed
        } else {
            // Couldn't fix this one, give up
            break
        }
    }

    return currentCode
}

/// Information about a problematic `#sourceLocation` directive.
private struct ProblematicDirective {
    /// The line index (0-based) where the directive appears.
    let lineIndex: Int
    /// The line index (0-based) where the syntax error occurs.
    let errorLineIndex: Int
}

/// Result of parsing code and looking for problematic directives.
private struct ParseResult {
    /// Problematic directives found, ordered by line index.
    let problematicDirectives: [ProblematicDirective]
}

/// Parses Swift code and finds `#sourceLocation` directives causing syntax errors.
private func parseAndFindProblematicDirectives(_ code: String) -> ParseResult {
    // Parse the code
    let sourceFile = Parser.parse(source: code)
    let converter = SourceLocationConverter(fileName: "", tree: sourceFile)
    
    
    var problematic: [ProblematicDirective] = []

    // Walk the tree looking for Unexpected nodes containing #sourceLocation directives
    class UnexpectedVisitor: SyntaxVisitor {
        let converter: SourceLocationConverter
        let tokens: [TokenSyntax]
        var problematic: [ProblematicDirective] = []
        var foundDirectives = Set<Int>()

        init(converter: SourceLocationConverter, tokens: [TokenSyntax]) {
            self.converter = converter
            self.tokens = tokens
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: UnexpectedNodesSyntax) -> SyntaxVisitorContinueKind {
            let startPos = node.position
            let endPos = node.endPosition
            let startLine = converter.location(for: startPos).line
            let endLine = converter.location(for: endPos).line
            
            let unexpectedTokens = Array(node.tokens(viewMode: .sourceAccurate))
            
            // Check if any tokens in this unexpected node are #sourceLocation directives
            for token in node.tokens(viewMode: .sourceAccurate) {
                if token.tokenKind == .poundSourceLocation {
                    let lineIndex = converter.location(for: token.position).line
                    if !foundDirectives.contains(lineIndex) {
                        problematic.append(
                            ProblematicDirective(
                                lineIndex: lineIndex,
                                errorLineIndex: lineIndex
                            )
                        )
                        foundDirectives.insert(lineIndex)
                    }
                }
            }

            // Also look for #sourceLocation directives adjacent to this unexpected node
            guard let firstUnexpectedToken = unexpectedTokens.first else {
                return .visitChildren
            }

            // Find the index of this unexpected token in the full token list
            guard
                let unexpectedIndex = tokens.firstIndex(where: {
                    $0.position == firstUnexpectedToken.position
                })
            else {
                return .visitChildren
            }

            for (tokenIndex, token) in tokens.enumerated() {
                guard token.tokenKind == .poundSourceLocation else { continue }

                // A #sourceLocation directive is always exactly 12 tokens:
                // #sourceLocation ( file : " string " , line : int )
                // The directive ends at tokenIndex + 11
                let directiveEndIndex = tokenIndex + 11

                // Check if the directive is directly adjacent to the unexpected node
                // (next token is the start of unexpected)
                if directiveEndIndex + 1 == unexpectedIndex {
                    let directiveLineIndex = converter.location(for: token.position).line
                    if !foundDirectives.contains(directiveLineIndex) {
                        let unexpectedLineIndex = converter.location(for: node.position).line
                        problematic.append(
                            ProblematicDirective(
                                lineIndex: directiveLineIndex, errorLineIndex: unexpectedLineIndex)
                        )
                        foundDirectives.insert(directiveLineIndex)
                    }
                }
            }

            return .visitChildren
        }
    }

    let tokens = Array(sourceFile.tokens(viewMode: .sourceAccurate))
    let visitor = UnexpectedVisitor(converter: converter, tokens: tokens)
    visitor.walk(sourceFile)

    problematic = visitor.problematic

    // All problematic directives are detected by checking UnexpectedNodesSyntax above.
    // No need for separate missing token or proximity checks.

    return ParseResult(problematicDirectives: problematic.sorted { $0.lineIndex < $1.lineIndex })
}

/// Attempts to fix the first problematic directive by moving it token-by-token.
///
/// Returns the fixed code if successful, or `nil` if the directive should be discarded.
private func fixFirstProblematicDirective(
    _ code: String, _ problematicDirectives: [ProblematicDirective]
) -> String? {
    guard let directive = problematicDirectives.first else {
        return nil
    }

    // Parse and get all tokens
    let sourceFile = Parser.parse(source: code)
    let converter = SourceLocationConverter(fileName: "", tree: sourceFile)
    var tokens = Array(sourceFile.tokens(viewMode: .sourceAccurate))

    // Find the directive's starting token index
    var directiveTokenIndex: Int? = nil
    for (idx, token) in tokens.enumerated() {
        if token.tokenKind == .poundSourceLocation {
            let line = converter.location(for: token.position).line
            if line == directive.lineIndex {
                directiveTokenIndex = idx
                break
            }
        }
    }

    guard let startIdx = directiveTokenIndex else {
        return code
    }

    // Extract the 12-token directive
    guard startIdx + 11 < tokens.count else {
        return code
    }

    let directiveTokens = Array(tokens[startIdx..<startIdx + 12])

    // Capture trivia from the directive
    let leadingTrivia = directiveTokens[0].leadingTrivia
    let trailingTrivia = directiveTokens[11].trailingTrivia
    
    // Split leading trivia at the LAST newline
    let leadingPieces = Array(leadingTrivia)
    var lastNewlineIndex: Int? = nil
    for (i, piece) in leadingPieces.enumerated().reversed() {
        if piece.isNewline {
            lastNewlineIndex = i
            break
        }
    }

    let (leadingToTransfer, leadingToKeep): (Trivia, Trivia)
    if let idx = lastNewlineIndex {
        // Transfer everything before the last newline, keep the newline and after
        leadingToTransfer = Trivia(pieces: Array(leadingPieces[0..<idx]))
        leadingToKeep = Trivia(pieces: Array(leadingPieces[idx...]))
    } else {
        // No newline in leading trivia
        if startIdx > 0 {
            // Has previous token, transfer all leading trivia
            leadingToTransfer = leadingTrivia
            leadingToKeep = Trivia()
        } else {
            // No previous token, keep all leading trivia
            leadingToTransfer = Trivia()
            leadingToKeep = leadingTrivia
        }
    }
    
    // Split trailing trivia at the FIRST newline
    let trailingPieces = Array(trailingTrivia)
    var firstNewlineIndex: Int? = nil
    for (i, piece) in trailingPieces.enumerated() {
        if piece.isNewline {
            firstNewlineIndex = i
            break
        }
    }
    
    let (trailingToKeep, trailingToTransfer): (Trivia, Trivia)
    let tokenAfterIndex = startIdx + 12
    if let idx = firstNewlineIndex {
        // Keep the newline and everything before it, transfer everything after
        trailingToKeep = Trivia(pieces: Array(trailingPieces[0...idx]))
        trailingToTransfer = Trivia(pieces: Array(trailingPieces[(idx+1)...]))
    } else {
        // No newline in trailing trivia
        if tokenAfterIndex < tokens.count {
            // Has next token, transfer all trailing trivia
            trailingToKeep = Trivia()
            trailingToTransfer = trailingTrivia
        } else {
            // No next token, keep all trailing trivia
            trailingToKeep = trailingTrivia
            trailingToTransfer = Trivia()
        }
    }
    
    // Create directive tokens with the trivia to keep
    var directiveToMove = directiveTokens
    directiveToMove[0] = directiveToMove[0].with(\.leadingTrivia, leadingToKeep)
    directiveToMove[11] = directiveToMove[11].with(\.trailingTrivia, trailingToKeep)
    
    // Extract the original line number from token[10]
    guard let originalLineNumber = Int(directiveTokens[10].text) else {
        return code
    }

    // Transfer trivia to surrounding tokens before removing the directive
    if !leadingToTransfer.isEmpty && startIdx > 0 {
        tokens[startIdx - 1] = tokens[startIdx - 1].with(
            \.trailingTrivia, 
            tokens[startIdx - 1].trailingTrivia + leadingToTransfer
        )
    }
    
    if !trailingToTransfer.isEmpty && tokenAfterIndex < tokens.count {
        tokens[tokenAfterIndex] = tokens[tokenAfterIndex].with(
            \.leadingTrivia,
            trailingToTransfer + tokens[tokenAfterIndex].leadingTrivia
        )
    }

    // Remove the directive from the token stream
    tokens.removeSubrange(startIdx..<startIdx + 12)

    // Try inserting at subsequent positions
    // Start at the position where the directive was (now occupied by what was after it)
    var insertPos = startIdx
    var updatedLineNumber = originalLineNumber

    while insertPos <= tokens.count {
        // Check if there's already a #sourceLocation at this position
        if insertPos < tokens.count && tokens[insertPos].tokenKind == .poundSourceLocation {
            // Skip past this directive (12 tokens)
            insertPos += 12
            updatedLineNumber += 1
            continue
        }

        // Insert the directive at this position with its preserved newlines
        tokens.insert(contentsOf: directiveToMove, at: insertPos)

        // Reconstruct source from tokens to calculate actual line numbers
        let reconstructed = tokens.map { $0.description }.joined()
        
        // Parse to find what line the directive we just inserted ended up on
        let tempSourceFile = Parser.parse(source: reconstructed)
        let tempConverter = SourceLocationConverter(fileName: "", tree: tempSourceFile)
        
        // Find the directive we just inserted (at the insertPos token position)
        let tokensAfterInsertion = Array(tempSourceFile.tokens(viewMode: .sourceAccurate))
        var ourDirectiveLineInReconstructed: Int? = nil
        
        // The directive we inserted should be at token index insertPos
        if insertPos < tokensAfterInsertion.count {
            let tokenAtInsertPos = tokensAfterInsertion[insertPos]
            if tokenAtInsertPos.tokenKind == .poundSourceLocation {
                ourDirectiveLineInReconstructed = tempConverter.location(for: tokenAtInsertPos.position).line
            }
        }
        
        // Update the line number to point to the line after the directive
        // SwiftSyntax uses 0-based line numbering, but #sourceLocation uses 1-based
        if let directiveLine = ourDirectiveLineInReconstructed {
            let nextLineZeroBased = directiveLine + 1
            let nextLineOneBased = nextLineZeroBased + 1
            // Remove the directive we just inserted
            tokens.removeSubrange(insertPos..<insertPos + 12)
            // Create updated directive with correct line number, preserving the trivia
            var updatedDirective = directiveToMove
            updatedDirective[10] = TokenSyntax(
                .integerLiteral(String(nextLineOneBased)),
                presence: .present
            )
            // Re-insert with updated line number
            tokens.insert(contentsOf: updatedDirective, at: insertPos)
        }

        // Reconstruct source again with updated line number
        let finalReconstructed = tokens.map { $0.description }.joined()

        // Check if THIS SPECIFIC directive is still problematic
        let parseResult = parseAndFindProblematicDirectives(finalReconstructed)
        
        // Check if our directive (at the line where we placed it) is still in the problematic list
        let ourDirectiveStillProblematic = ourDirectiveLineInReconstructed.map { ourLine in
            parseResult.problematicDirectives.contains { $0.lineIndex == ourLine }
        } ?? true  // If we couldn't find our directive, assume it's still problematic
        
        if !ourDirectiveStillProblematic {
            return finalReconstructed
        }

        // Still problematic, remove and try next position
        tokens.removeSubrange(insertPos..<insertPos + 12)
        insertPos += 1
        updatedLineNumber += 1
    }

    // Exhausted all positions, discard the directive
    return tokens.map { $0.description }.joined()
}
