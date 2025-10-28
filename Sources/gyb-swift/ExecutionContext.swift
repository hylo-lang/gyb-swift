import Algorithms
import Foundation

// MARK: - Cross-platform path utilities

extension URL {
  /// The representation used by the native filesystem.
  var platformString: String {
    self.withUnsafeFileSystemRepresentation { String(cString: $0!) }
  }
}

// MARK: - Errors

/// Errors that can occur during template execution.
enum GYBError: Error, CustomStringConvertible {
  /// Generated Swift code failed during compilation or execution, with error output.
  case executionFailed(filename: String, errorOutput: String)

  var description: String {
    switch self {
    case .executionFailed(let filename, let errorOutput):
      return "Error executing generated code from \(filename)\n\(errorOutput)"
    }
  }
}

// MARK: - AST to Swift Code Conversion

/// Generates Swift code from AST nodes with consistent configuration.
struct CodeGenerator {
  /// Original template text for source location tracking.
  let templateText: String
  /// Template filename for source location directives.
  let filename: String
  /// Line directive format for output with `\(file)` and `\(line)` placeholders, or empty to omit.
  let lineDirective: String
  /// Whether to emit line directives in the template output.
  let emitLineDirectives: Bool

  /// Precomputed line start positions for efficient line number calculation.
  private let lineStarts: [String.Index]

  init(
    templateText: String,
    filename: String = "",
    lineDirective: String = "",
    emitLineDirectives: Bool = false
  ) {
    self.templateText = templateText
    self.filename = filename
    self.lineDirective = lineDirective
    self.emitLineDirectives = emitLineDirectives
    self.lineStarts = getLineStarts(templateText)
  }

  /// Returns Swift code executing `nodes`, batching consecutive nodes of the same type.
  func generateCode(for nodes: [ASTNode]) -> String {
    // Group consecutive nodes: output nodes together, code nodes together
    let chunks = nodes.chunked { prev, curr in
      (isOutputNode(prev) && isOutputNode(curr)) || (prev is CodeNode && curr is CodeNode)
    }

    let lines = chunks.map { chunk -> String in
      // Code nodes: emit with source location directive at the start
      if let firstCode = chunk.first as? CodeNode {
        let lineNumber =
          getLineNumber(
            for: firstCode.sourcePosition, in: templateText, lineStarts: lineStarts)
        let sourceLocationDirective = formatSourceLocation(
          #"#sourceLocation(file: "\(file)", line: \(line))"#,
          filename: filename,
          line: lineNumber
        )
        // Concatenate all code from consecutive code nodes
        let codeLines = chunk.compactMap { ($0 as? CodeNode)?.code }.map(String.init)
        return sourceLocationDirective + "\n" + codeLines.joined(separator: "\n")
      }

      // Output nodes are batched into print statements
      return printStatement(for: chunk)
    }

    return lines.joined(separator: "\n")
  }

  /// Returns a complete Swift program for `ast` with `bindings`.
  func generateCompleteProgram(_ ast: AST, bindings: [String: String] = [:]) -> String {
    // Generate bindings code
    let bindingsCode =
      bindings
      .map { "let \($0.key) = \(String(reflecting: $0.value))" }
      .joined(separator: "\n")

    // Generate template code
    let templateCode = generateCode(for: ast)

    let code = """
      import Foundation

      // Bindings
      \(bindingsCode)

      // Generated code
      \(templateCode)

      """

    // Fix any misplaced #sourceLocation directives
    return fixSourceLocationPlacement(code)
  }

  /// Executes `ast` with `bindings` using Swift interpreter or compilation.
  ///
  /// By default, uses the Swift interpreter on non-Windows platforms for faster execution.
  /// On Windows or when `forceCompilation` is true, compiles and runs the generated code.
  func execute(
    _ ast: AST, bindings: [String: String] = [:], forceCompilation: Bool = false
  ) throws -> String {
    let swiftCode = generateCompleteProgram(ast, bindings: bindings)

    return
      (isWindows || forceCompilation)
      ? try executeViaCompilation(swiftCode)
      : try executeViaInterpreter(swiftCode)
  }

  /// Executes `swiftCode` using the Swift interpreter (fast).
  private func executeViaInterpreter(_ swiftCode: String) throws -> String {
    let tempDir = FileManager.default.temporaryDirectory
    let temp = tempDir.appendingPathComponent("gyb_\(UUID().uuidString).swift")

    defer {
      try? FileManager.default.removeItem(at: temp)
    }

    try swiftCode.write(to: temp, atomically: true, encoding: .utf8)

    let p = try processForCommand("swift", arguments: [temp.platformString])

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    p.standardOutput = outputPipe
    p.standardError = errorPipe

    try p.run()
    p.waitUntilExit()

    if p.terminationStatus != 0 {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
      throw GYBError.executionFailed(filename: filename, errorOutput: errorOutput)
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: outputData, encoding: .utf8) ?? ""
  }

  /// Executes `swiftCode` by compiling and running the executable.
  private func executeViaCompilation(_ swiftCode: String) throws -> String {
    let tempDir = FileManager.default.temporaryDirectory
    let uuid = UUID().uuidString
    let sourceFile = tempDir.appendingPathComponent("gyb_\(uuid).swift")
    let executableFile = tempDir.appendingPathComponent("gyb_\(uuid)")
    let moduleCacheDir = tempDir.appendingPathComponent("gyb_\(uuid)_modules")

    defer {
      try? FileManager.default.removeItem(at: sourceFile)
      try? FileManager.default.removeItem(at: executableFile)
      try? FileManager.default.removeItem(at: moduleCacheDir)
      // On Windows, also try to remove .exe
      try? FileManager.default.removeItem(
        at: tempDir.appendingPathComponent("gyb_\(uuid).exe"))
    }

    try swiftCode.write(to: sourceFile, atomically: true, encoding: .utf8)

    let compileProcess = try processForCommand(
      "swiftc",
      arguments: [
        sourceFile.platformString,
        "-o", executableFile.platformString,
        "-module-cache-path", moduleCacheDir.platformString,
      ])

    let compileError = Pipe()
    compileProcess.standardOutput = Pipe()
    compileProcess.standardError = compileError

    try compileProcess.run()
    compileProcess.waitUntilExit()

    if compileProcess.terminationStatus != 0 {
      let errorData = compileError.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
      throw GYBError.executionFailed(filename: filename, errorOutput: errorOutput)
    }

    let runProcess = try processForCommand(
      executableFile.platformString, arguments: [])

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    runProcess.standardOutput = outputPipe
    runProcess.standardError = errorPipe

    try runProcess.run()
    runProcess.waitUntilExit()

    if runProcess.terminationStatus != 0 {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
      throw GYBError.executionFailed(filename: filename, errorOutput: errorOutput)
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: outputData, encoding: .utf8) ?? ""
  }

  /// Returns the start position of `nodes`'s first element.
  private func sourceLocationIndex(for nodes: AST.SubSequence) -> String.Index {
    let first = nodes.first!

    if let literal = first as? LiteralNode {
      return literal.text.startIndex
    } else if let substitution = first as? SubstitutionNode {
      return substitution.expression.startIndex
    }
    fatalError("Unexpected node type: \(type(of: first))")
  }

  /// Returns `nodes`'s text content as strings, with substitutions formatted as `\(expression)`.
  private func textContent(from nodes: AST.SubSequence) -> [String] {
    return nodes.map { node in
      if let literal = node as? LiteralNode {
        return String(literal.text)
      } else if let substitution = node as? SubstitutionNode {
        return #"\(\#(substitution.expression))"#
      }
      fatalError("Unexpected node type: \(type(of: node))")
    }
  }

  /// Returns a Swift print statement outputting `nodes`'s combined text.
  ///
  /// Always includes a `#sourceLocation` directive in the generated Swift code for error reporting.
  /// Optionally prints line directives into the output when configured.
  private func printStatement(for nodes: AST.SubSequence) -> String {
    let combined = textContent(from: nodes).joined()
    var swiftCode: [String] = []

    // Always emit #sourceLocation in the intermediate Swift code for error reporting
    let index = sourceLocationIndex(for: nodes)
    let lineNumber = getLineNumber(for: index, in: templateText, lineStarts: lineStarts)
    let sourceLocationDirective = formatSourceLocation(
      #"#sourceLocation(file: "\(file)", line: \(line))"#,
      filename: filename,
      line: lineNumber
    )
    swiftCode.append(sourceLocationDirective)

    // Optionally print line directives into the output
    var output = combined
    if emitLineDirectives && !lineDirective.isEmpty {
      let outputDirective = formatSourceLocation(
        lineDirective, filename: filename, line: lineNumber)
      output = outputDirective + "\n" + output
    }

    let escaped = escapeForSwiftMultilineString(output)
    swiftCode.append(
      #"print(""""#
        + "\n\(escaped)\n"
        + #"""", terminator: "")"#)

    return swiftCode.joined(separator: "\n")
  }

  /// Returns whether `node` represents template output.
  private func isOutputNode(_ node: ASTNode) -> Bool {
    return node is LiteralNode || node is SubstitutionNode
  }
}

/// Returns `text` escaped for Swift multiline string literals, preserving `\(...)` interpolations.
private func escapeForSwiftMultilineString(_ text: String) -> String {
  return
    text
    .replacingOccurrences(of: #"\"#, with: #"\\"#)
    .replacingOccurrences(of: #"""""#, with: #"\"\"\""#)
    // Undo escaping for interpolations so \(expr) is undisturbed.
    .replacingOccurrences(of: #"\\("#, with: #"\("#)
}

/// Returns `template`'s `\(file)` and `\(line)` placeholders replaced by `filename` and `line`.
private func formatSourceLocation(_ template: String, filename: String, line: Int) -> String {
  return
    template
    .replacingOccurrences(of: #"\(file)"#, with: filename)
    .replacingOccurrences(of: #"\(line)"#, with: "\(line)")
}
