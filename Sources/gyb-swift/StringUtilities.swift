import Algorithms
import Foundation

// MARK: - Lines

/// Content split into lines with precomputed line boundaries.
///
/// Provides efficient line-based operations on string content, treating each line
/// as a separate element in a random-access collection.
struct Lines<Content: StringProtocol>: RandomAccessCollection {
  /// The source content.
  let content: Content
  /// Start index of each line followed by `content.endIndex`.
  let lineBounds: [Content.Index]

  /// Creates lines from `content`.
  init(_ content: Content) {
    self.content = content
    self.lineBounds = Self.lineBounds(content)
  }

  /// Creates lines from `content` using precomputed `lineBounds`.
  init(content: Content, lineBounds: [Content.Index]) {
    self.content = content
    self.lineBounds = lineBounds
  }

  /// The type of a line (a substring of the content).
  typealias Element = Content.SubSequence

  /// The type of an index into lines.
  typealias Index = Int

  /// The start index (always 0).
  var startIndex: Index { 0 }

  /// The end index (one past the last line).
  var endIndex: Index { lineBounds.count - 1 }

  /// Returns the line at `position`.
  subscript(position: Index) -> Element {
    precondition(position >= 0 && position < lineBounds.count - 1, "Line index out of bounds")
    let lineStart = lineBounds[position]
    let lineEnd = lineBounds[position + 1]
    return content[lineStart..<lineEnd]
  }

  /// Returns the lines in `bounds`.
  subscript(bounds: Range<Index>) -> Lines<Content.SubSequence> {
    precondition(bounds.lowerBound >= 0 && bounds.upperBound <= lineBounds.count - 1)
    let contentStart =
      bounds.lowerBound == 0
      ? content.startIndex
      : lineBounds[bounds.lowerBound - 1]
    let contentEnd =
      bounds.upperBound == lineBounds.count - 1
      ? content.endIndex
      : lineBounds[bounds.upperBound]
    let slicedContent = content[contentStart..<contentEnd]
    return Lines<Content.SubSequence>(slicedContent)
  }

  /// Returns the 1-based line number for `position` in the original content.
  func lineNumber(at position: Content.Index) -> Int {
    // Use binary search to find the first line boundary that is after the given position
    // lineBounds is sorted, so partitioningIndex performs O(log N) binary search
    return lineBounds.partitioningIndex { $0 > position }
  }

  /// Returns the 0-based line index containing `position`, or `nil` if out of bounds.
  func lineIndex(at position: Content.Index) -> Int? {
    guard position >= content.startIndex && position <= content.endIndex else {
      return nil
    }
    let lineNum = lineNumber(at: position)
    return lineNum > 0 ? lineNum - 1 : nil
  }

  /// Returns line boundaries for `content`.
  private static func lineBounds(_ content: Content) -> [Content.Index] {
    // Uses split to handle all newline types (LF, CR, CRLF) correctly.
    // Split by newlines and get the start index of each segment
    let bounds = content.split(omittingEmptySubsequences: false) { $0.isNewline }
      .map(\.startIndex)
    return bounds + [content.endIndex]
  }
}

// MARK: - String Utilities

extension StringProtocol {
  /// Returns `self` split into lines with precomputed boundaries.
  func lines() -> Lines<Self> {
    Lines(self)
  }
}
