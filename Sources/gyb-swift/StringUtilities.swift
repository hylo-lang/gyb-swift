import Foundation
import Algorithms

// MARK: - String Utilities

/// Returns the start of each line in `text` followed by `text.endIndex`.
func getLineStarts(_ text: String) -> [String.Index] {
    text.split(omittingEmptySubsequences: false) { $0.isNewline }
        .map(\.startIndex) + [text.endIndex]
}

/// Returns the 1-based line number for a given index in the text.
func getLineNumber(for index: String.Index, in text: String, lineStarts: [String.Index]) -> Int {
    // Use binary search to find the first line start that is after the given index
    // lineStarts is sorted, so partitioningIndex performs O(log N) binary search
    return lineStarts.partitioningIndex { $0 > index }
}

