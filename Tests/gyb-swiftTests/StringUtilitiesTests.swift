import Testing

@testable import gyb_swift

@Test("getLineStarts with multi-line text")
func getLineStarts_multiLine() throws {
  let text = "line1\nline2\nline3"
  let starts = getLineStarts(text)

  #expect(starts.count == 4)
  #expect(starts[0] == text.startIndex)
  #expect(starts.last == text.endIndex)
}

@Test("getLineStarts with empty string")
func getLineStarts_empty() {
  let starts = getLineStarts("")
  #expect(starts.count == 2)
  #expect(starts[0] == "".startIndex)
  #expect(starts[1] == "".endIndex)
}

@Test("getLineStarts with single line")
func getLineStarts_singleLine() {
  let text = "single line"
  let starts = getLineStarts(text)
  #expect(starts.count == 2)
  #expect(starts[0] == text.startIndex)
  #expect(starts[1] == text.endIndex)
}

@Test("getLineStarts handles different newline types")
func getLineStarts_differentNewlines() {
  #expect(getLineStarts("a\nb").count == 3)  // LF
  #expect(getLineStarts("a\rb").count == 3)  // CR
  #expect(getLineStarts("a\r\nb").count == 3)  // CRLF (note: \r\n is one Character)
}
