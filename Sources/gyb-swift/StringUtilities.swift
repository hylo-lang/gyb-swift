import Algorithms
import Foundation

// MARK: - String Utilities

extension String {
  /// Returns the start of each line followed by `endIndex`.
  func lineBounds() -> [String.Index] {
    split(omittingEmptySubsequences: false) { $0.isNewline }
      .map(\.startIndex) + [endIndex]
  }

  /// Returns the 1-based line number for `index`.
  func lineNumber(at index: String.Index, lineBounds: [String.Index]) -> Int {
    // Use binary search to find the first line boundary that is after the given index
    // lineBounds is sorted, so partitioningIndex performs O(log N) binary search
    return lineBounds.partitioningIndex { $0 > index }
  }
}
