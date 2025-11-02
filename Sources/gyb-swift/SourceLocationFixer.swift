import Foundation
import SwiftParser
import SwiftSyntax

/// Returns `swiftSource` with any illegally-placed `#sourceLocation`
/// directives adjusted for syntactic validity, or discards them if
/// that isn't possible.
func fixSourceLocationPlacement(_ swiftSource: String) -> String {
  var currentCode = swiftSource

  // Keep trying to fix until no more fixes are needed
  while true {
    let problematicLineIndices = parseAndFindProblematicDirectives(currentCode)

    if problematicLineIndices.isEmpty {
      break
    }

    // Fix the first problematic directive (either move it or discard it)
    currentCode = fixFirstProblematicDirective(currentCode, problematicLineIndices)
  }

  return currentCode
}

/// Visitor that finds `#sourceLocation` directives within or adjacent to
/// `UnexpectedNodesSyntax` nodes.
private class UnexpectedVisitor: SyntaxVisitor {
  let converter: SourceLocationConverter
  let tokens: [TokenSyntax]
  var problematicLineIndices: [Int] = []
  var foundDirectives = Set<Int>()

  init(converter: SourceLocationConverter, tokens: [TokenSyntax]) {
    self.converter = converter
    self.tokens = tokens
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: UnexpectedNodesSyntax) -> SyntaxVisitorContinueKind {
    recordDirectivesWithinUnexpectedNode(node)
    recordDirectivesAdjacentToUnexpectedNode(node)
    return .visitChildren
  }

  /// Records `#sourceLocation` directives found within `node`.
  private func recordDirectivesWithinUnexpectedNode(_ node: UnexpectedNodesSyntax) {
    for token in node.tokens(viewMode: .sourceAccurate) {
      if token.tokenKind == .poundSourceLocation {
        let lineIndex = converter.location(for: token.position).line
        if !foundDirectives.contains(lineIndex) {
          problematicLineIndices.append(lineIndex)
          foundDirectives.insert(lineIndex)
        }
      }
    }
  }

  /// Records `#sourceLocation` directives immediately preceding `node` in the token stream.
  private func recordDirectivesAdjacentToUnexpectedNode(_ node: UnexpectedNodesSyntax) {
    let unexpectedTokens = Array(node.tokens(viewMode: .sourceAccurate))
    guard let firstUnexpectedToken = unexpectedTokens.first else { return }

    guard
      let unexpectedIndex = tokens.firstIndex(where: {
        $0.position == firstUnexpectedToken.position
      })
    else { return }

    for (tokenIndex, token) in tokens.enumerated() {
      guard token.tokenKind == .poundSourceLocation else { continue }

      // A #sourceLocation directive is always exactly 12 tokens:
      // #sourceLocation ( file : " string " , line : int )
      let directiveEndIndex = tokenIndex + 11

      if directiveEndIndex + 1 == unexpectedIndex {
        let directiveLineIndex = converter.location(for: token.position).line
        if !foundDirectives.contains(directiveLineIndex) {
          problematicLineIndices.append(directiveLineIndex)
          foundDirectives.insert(directiveLineIndex)
        }
      }
    }
  }
}

/// Parses Swift code and finds `#sourceLocation` directives causing syntax errors.
///
/// Returns the line indices (0-based) where problematic directives appear.
private func parseAndFindProblematicDirectives(_ code: String) -> [Int] {
  let parsed = SwiftParser.Parser.parse(source: code)
  let converter = SourceLocationConverter(fileName: "", tree: parsed)
  let tokens = Array(parsed.tokens(viewMode: .sourceAccurate))
  let visitor = UnexpectedVisitor(converter: converter, tokens: tokens)
  visitor.walk(parsed)

  return visitor.problematicLineIndices.sorted()
}

/// The token index where a `#sourceLocation` directive at `lineIndex` begins,
/// or `nil` if not found.
private func findDirectiveTokenIndex(
  in tokens: [TokenSyntax], at lineIndex: Int, converter: SourceLocationConverter
) -> Int? {
  for (idx, token) in tokens.enumerated() {
    if token.tokenKind == .poundSourceLocation {
      let line = converter.location(for: token.position).line
      if line == lineIndex {
        return idx
      }
    }
  }
  return nil
}

/// Directive tokens with trivia split so newlines stay with the directive,
/// and trivia to transfer to surrounding tokens.
private func splitTriviaSurroundingDirective(
  _ directiveTokens: [TokenSyntax], hasPreviousToken: Bool, hasNextToken: Bool
) -> (directive: [TokenSyntax], leadingToTransfer: Trivia, trailingToTransfer: Trivia) {
  let leadingTrivia = directiveTokens[0].leadingTrivia
  let trailingTrivia = directiveTokens[11].trailingTrivia

  let leadingPieces = Array(leadingTrivia)
  let lastNewlineIndex = leadingPieces.lastIndex { $0.isNewline }

  let (leadingToTransfer, leadingToKeep): (Trivia, Trivia)
  if let idx = lastNewlineIndex {
    leadingToTransfer = Trivia(pieces: Array(leadingPieces[0..<idx]))
    leadingToKeep = Trivia(pieces: Array(leadingPieces[idx...]))
  } else if hasPreviousToken {
    leadingToTransfer = leadingTrivia
    leadingToKeep = Trivia()
  } else {
    leadingToTransfer = Trivia()
    leadingToKeep = leadingTrivia
  }

  let trailingPieces = Array(trailingTrivia)
  let firstNewlineIndex = trailingPieces.firstIndex { $0.isNewline }

  let (trailingToKeep, trailingToTransfer): (Trivia, Trivia)
  if let idx = firstNewlineIndex {
    trailingToKeep = Trivia(pieces: Array(trailingPieces[0...idx]))
    trailingToTransfer = Trivia(pieces: Array(trailingPieces[(idx + 1)...]))
  } else if hasNextToken {
    trailingToKeep = Trivia()
    trailingToTransfer = trailingTrivia
  } else {
    trailingToKeep = trailingTrivia
    trailingToTransfer = Trivia()
  }

  var result = directiveTokens
  result[0] = result[0].with(\.leadingTrivia, leadingToKeep)
  result[11] = result[11].with(\.trailingTrivia, trailingToKeep)

  return (result, leadingToTransfer, trailingToTransfer)
}

/// Transfers trivia from a directive to surrounding tokens before the directive is removed.
private func transferTriviaToSurroundingTokens(
  _ tokens: inout [TokenSyntax], at directiveIndex: Int, leading: Trivia, trailing: Trivia
) {
  if !leading.isEmpty && directiveIndex > 0 {
    tokens[directiveIndex - 1] = tokens[directiveIndex - 1].with(
      \.trailingTrivia,
      tokens[directiveIndex - 1].trailingTrivia + leading
    )
  }

  if !trailing.isEmpty && directiveIndex + 12 < tokens.count {
    tokens[directiveIndex + 12] = tokens[directiveIndex + 12].with(
      \.leadingTrivia,
      trailing + tokens[directiveIndex + 12].leadingTrivia
    )
  }
}

/// The line index (0-based) where the directive at `tokenIndex` is located, or `nil` if not found.
private func findDirectiveLineAfterInsertion(
  _ tokens: [TokenSyntax], at tokenIndex: Int, in code: String
) -> Int? {
  let parsed = SwiftParser.Parser.parse(source: code)
  let converter = SourceLocationConverter(fileName: "", tree: parsed)
  let tokensAfterInsertion = Array(parsed.tokens(viewMode: .sourceAccurate))

  guard tokenIndex < tokensAfterInsertion.count else { return nil }

  let tokenAtInsertPos = tokensAfterInsertion[tokenIndex]
  guard tokenAtInsertPos.tokenKind == .poundSourceLocation else { return nil }

  return converter.location(for: tokenAtInsertPos.position).line
}

/// Directive tokens with the line number updated to point to the line after `directiveLine`.
private func directiveWithUpdatedLineNumber(
  _ directive: [TokenSyntax], directiveLine: Int
) -> [TokenSyntax] {
  let nextLineZeroBased = directiveLine + 1
  let nextLineOneBased = nextLineZeroBased + 1

  var updatedDirective = directive
  updatedDirective[10] = TokenSyntax(
    .integerLiteral(String(nextLineOneBased)),
    presence: .present
  )
  return updatedDirective
}

/// Code with the directive successfully moved to a valid position, or `nil` if no valid position found.
private func tryMovingDirective(
  _ directive: [TokenSyntax], inTokens tokens: inout [TokenSyntax], startingAt startIndex: Int
) -> String? {
  var insertPos = startIndex

  while insertPos <= tokens.count {
    if insertPos < tokens.count && tokens[insertPos].tokenKind == .poundSourceLocation {
      insertPos += 12
      continue
    }

    tokens.insert(contentsOf: directive, at: insertPos)
    let reconstructed = tokens.map { $0.description }.joined()

    if let directiveLine = findDirectiveLineAfterInsertion(
      tokens, at: insertPos, in: reconstructed)
    {
      tokens.removeSubrange(insertPos..<insertPos + 12)
      let updatedDirective = directiveWithUpdatedLineNumber(
        directive, directiveLine: directiveLine)
      tokens.insert(contentsOf: updatedDirective, at: insertPos)
    }

    let finalReconstructed = tokens.map { $0.description }.joined()
    let problematicLineIndices = parseAndFindProblematicDirectives(finalReconstructed)

    if let directiveLine = findDirectiveLineAfterInsertion(
      tokens, at: insertPos, in: finalReconstructed)
    {
      if !problematicLineIndices.contains(directiveLine) {
        return finalReconstructed
      }
    }

    tokens.removeSubrange(insertPos..<insertPos + 12)
    insertPos += 1
  }

  return nil
}

/// Attempts to fix the first problematic directive by moving it token-by-token.
///
/// If the directive can be moved to a valid position, returns the code with the directive moved.
/// If no valid position exists, returns the code with the directive discarded.
private func fixFirstProblematicDirective(
  _ code: String, _ problematicLineIndices: [Int]
) -> String {
  guard let directiveLineIndex = problematicLineIndices.first else {
    return code
  }

  let parsed = SwiftParser.Parser.parse(source: code)
  let converter = SourceLocationConverter(fileName: "", tree: parsed)
  var tokens = Array(parsed.tokens(viewMode: .sourceAccurate))

  guard
    let startIdx = findDirectiveTokenIndex(
      in: tokens, at: directiveLineIndex, converter: converter),
    startIdx + 11 < tokens.count
  else {
    return code
  }

  let directiveTokens = Array(tokens[startIdx..<startIdx + 12])
  let (directiveToMove, leadingToTransfer, trailingToTransfer) =
    splitTriviaSurroundingDirective(
      directiveTokens, hasPreviousToken: startIdx > 0,
      hasNextToken: startIdx + 12 < tokens.count)

  transferTriviaToSurroundingTokens(
    &tokens, at: startIdx, leading: leadingToTransfer, trailing: trailingToTransfer)

  tokens.removeSubrange(startIdx..<startIdx + 12)

  if let fixed = tryMovingDirective(directiveToMove, inTokens: &tokens, startingAt: startIdx) {
    return fixed
  }

  return tokens.map { $0.description }.joined()
}
