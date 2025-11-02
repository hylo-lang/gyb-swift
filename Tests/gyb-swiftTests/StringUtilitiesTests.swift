import Testing

@testable import gyb_swift

@Test("Lines with multi-line text")
func lines_multiLine() throws {
  let text = "line1\nline2\nline3"
  let lines = Lines(text)
  #expect(lines.lineBounds.count == 4)
  #expect(lines.lineBounds[0] == text.startIndex)
  #expect(lines.lineBounds.last == text.endIndex)
  #expect(lines.count == 3)
  #expect(String(lines[0]) == "line1\n")
  #expect(String(lines[1]) == "line2\n")
  #expect(String(lines[2]) == "line3")
}

@Test("Lines with empty string")
func lines_empty() {
  let text = ""
  let lines = Lines(text)
  #expect(lines.lineBounds.count == 2)
  #expect(lines.lineBounds[0] == text.startIndex)
  #expect(lines.lineBounds[1] == text.endIndex)
  #expect(lines.count == 1)
  #expect(String(lines[0]) == "")
}

@Test("Lines with single line")
func lines_singleLine() {
  let text = "single line"
  let lines = Lines(text)
  #expect(lines.lineBounds.count == 2)
  #expect(lines.lineBounds[0] == text.startIndex)
  #expect(lines.lineBounds[1] == text.endIndex)
  #expect(lines.count == 1)
  #expect(String(lines[0]) == "single line")
}

@Test("Lines handles different newline types")
func lines_differentNewlines() {
  #expect(Lines("a\nb").lineBounds.count == 3)  // LF
  #expect(Lines("a\rb").lineBounds.count == 3)  // CR
  #expect(Lines("a\r\nb").lineBounds.count == 3)  // CRLF (note: \r\n is one Character)
}

@Test("Lines lineNumber method")
func lines_lineNumber() {
  let text = "line1\nline2\nline3"
  let lines = Lines(text)
  let line1End = text.index(text.startIndex, offsetBy: 5)  // After "line1"
  #expect(lines.lineNumber(at: text.startIndex) == 1)
  #expect(lines.lineNumber(at: line1End) == 1)
  let line2Start = text.index(line1End, offsetBy: 1)  // Start of line2
  #expect(lines.lineNumber(at: line2Start) == 2)
}

@Test("Lines collection behavior")
func lines_collection() {
  let text = "a\nb\nc"
  let lines = Lines(text)
  #expect(lines.count == 3)
  #expect(Array(lines).map(String.init) == ["a\n", "b\n", "c"])
}
