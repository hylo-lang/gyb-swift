import Testing

@testable import gyb_swift

@Test("lineBounds with multi-line text")
func lineBounds_multiLine() throws {
  let text = "line1\nline2\nline3"
  let bounds = text.lineBounds()
  #expect(bounds.count == 4)
  #expect(bounds[0] == text.startIndex)
  #expect(bounds.last == text.endIndex)
}

@Test("lineBounds with empty string")
func lineBounds_empty() {
  let text = ""
  let bounds = text.lineBounds()
  #expect(bounds.count == 2)
  #expect(bounds[0] == text.startIndex)
  #expect(bounds[1] == text.endIndex)
}

@Test("lineBounds with single line")
func lineBounds_singleLine() {
  let text = "single line"
  let bounds = text.lineBounds()
  #expect(bounds.count == 2)
  #expect(bounds[0] == text.startIndex)
  #expect(bounds[1] == text.endIndex)
}

@Test("lineBounds handles different newline types")
func lineBounds_differentNewlines() {
  #expect("a\nb".lineBounds().count == 3)  // LF
  #expect("a\rb".lineBounds().count == 3)  // CR
  #expect("a\r\nb".lineBounds().count == 3)  // CRLF (note: \r\n is one Character)
}
