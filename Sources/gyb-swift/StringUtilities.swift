import Foundation

// MARK: - String Utilities

/// Returns the start of each line in `text` followed by `text.endIndex`.
func getLineStarts(_ text: String) -> [String.Index] {
    text.split(omittingEmptySubsequences: false) { $0.isNewline }
        .map(\.startIndex) + [text.endIndex]
}

/// Returns `text` without its trailing newline, if any.
func stripTrailingNewline(_ text: String) -> String {
    guard let last = text.last, last.isNewline else { return text }
    return String(text.dropLast())
}


/// Returns lines from `text`, each with a trailing newline.
func splitLines(_ text: String) -> [String] {
    text.split(omittingEmptySubsequences: false) { $0.isNewline }
        .map { $0 + "\n" }
}
