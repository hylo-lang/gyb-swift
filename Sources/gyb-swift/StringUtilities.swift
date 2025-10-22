import Foundation

// MARK: - String Utilities

/// Returns the start of each line in `text` followed by `text.endIndex`.
func getLineStarts(_ text: String) -> [String.Index] {
    text.split(omittingEmptySubsequences: false) { $0.isNewline }
        .map(\.startIndex) + [text.endIndex]
}

