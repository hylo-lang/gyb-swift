import Foundation

// MARK: - String Utilities

/// Returns line start indices for the text.
///
/// The returned array contains the start index of each line in the text,
/// plus a sentinel index for the end of the string.
///
/// - Postcondition: result.count equals the number of lines plus one.
/// - Complexity: O(n) where n is the length of the text.
func getLineStarts(_ text: String) -> [String.Index] {
    var starts = [text.startIndex]
    var currentIndex = text.startIndex
    
    while currentIndex < text.endIndex {
        if text[currentIndex] == "\n" {
            let nextIndex = text.index(after: currentIndex)
            starts.append(nextIndex)
            currentIndex = nextIndex
        } else {
            currentIndex = text.index(after: currentIndex)
        }
    }
    
    // Add sentinel for end if not already added
    if starts.last != text.endIndex {
        starts.append(text.endIndex)
    }
    
    return starts
}

/// Removes trailing newline from the text if present.
///
/// - Returns: text with trailing newline removed, or text unchanged.
func stripTrailingNewline(_ text: String) -> String {
    text.hasSuffix("\n") ? String(text.dropLast()) : text
}

/// Splits text into lines, each preserving its trailing newline.
///
/// When concatenated, the result is the original text, possibly with a single
/// appended newline.
func splitLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map { $0 + "\n" }
}

