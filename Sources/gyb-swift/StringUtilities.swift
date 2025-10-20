import Foundation

// MARK: - String Utilities

/// Returns the start of each line in `text` followed by `text.endIndex`.
func getLineStarts(_ text: String) -> [String.Index] {
    text.split(omittingEmptySubsequences: false) { $0.isNewline }
        .map(\.startIndex) + [text.endIndex]
}

/// Returns `text` without its trailing newline, if any.
func stripTrailingNewline(_ text: String) -> String {
    text.hasSuffix("\n") ? String(text.dropLast()) : text
}

/// Returns lines from `text`, each with its trailing newline.
func splitLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map { $0 + "\n" }
}

