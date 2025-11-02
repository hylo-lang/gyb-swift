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
  /// Source template for location tracking.
  let sourceTemplate: Lines<String>
  /// Template filename for source location directives.
  let filename: String
  /// Line directive format for output with `\(file)` and `\(line)` placeholders, or empty to omit.
  let lineDirective: String
  /// Whether to emit line directives in the template output.
  let emitLineDirectives: Bool

  init(
    template: String,
    filename: String = "",
    lineDirective: String = "",
    emitLineDirectives: Bool = false
  ) {
    self.sourceTemplate = Lines(template)
    self.filename = filename
    self.lineDirective = lineDirective
    self.emitLineDirectives = emitLineDirectives
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
        let lineNumber = sourceTemplate.lineNumber(at: firstCode.sourcePosition)
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

    do {
      // On Windows, atomically: true can cause file locking issues
      try swiftCode.write(to: temp, atomically: !isWindows, encoding: .utf8)
    } catch {
      throw Failure("Failed to write temporary Swift file to '\(temp.path)'", error)
    }

    let result = try resultsOfRunning(["swift", temp.platformString])

    guard result.exitStatus == 0 else {
      throw GYBError.executionFailed(filename: filename, errorOutput: result.stderr)
    }

    return result.stdout.normalizingLineEndings()
  }

  /// Executes `swiftCode` by compiling and running the executable.
  private func executeViaCompilation(_ swiftCode: String) throws -> String {
    let tempFiles = createTempFiles()
    defer { cleanupTempFiles(tempFiles) }

    do {
      // On Windows, atomically: true can cause file locking issues
      try swiftCode.write(to: tempFiles.source, atomically: !isWindows, encoding: .utf8)
    } catch {
      throw Failure("Failed to write temporary Swift file to '\(tempFiles.source.path)'", error)
    }
    try compileSwiftCode(
      source: tempFiles.source, output: tempFiles.executable, moduleCache: tempFiles.moduleCache)
    return try runCompiledExecutable(tempFiles.executable)
  }

  /// Temporary files needed for compilation.
  private struct TempFiles {
    let source: URL
    let executable: URL
    let moduleCache: URL
  }

  /// Creates temporary files for compilation with platform-specific executable naming.
  private func createTempFiles() -> TempFiles {
    let tempDir = FileManager.default.temporaryDirectory
    let uuid = UUID().uuidString
    let source = tempDir.appendingPathComponent("gyb_\(uuid).swift")
    let moduleCache = tempDir.appendingPathComponent("gyb_\(uuid)_modules")

    // On Windows, executables must have .exe extension
    let executable =
      isWindows
      ? tempDir.appendingPathComponent("gyb_\(uuid).exe")
      : tempDir.appendingPathComponent("gyb_\(uuid)")

    return TempFiles(
      source: source,
      executable: executable,
      moduleCache: moduleCache
    )
  }

  /// Removes all temporary files, ignoring errors.
  private func cleanupTempFiles(_ files: TempFiles) {
    try? FileManager.default.removeItem(at: files.source)
    try? FileManager.default.removeItem(at: files.executable)
    try? FileManager.default.removeItem(at: files.moduleCache)
  }

  /// Compiles Swift source file to executable.
  private func compileSwiftCode(source: URL, output: URL, moduleCache: URL) throws {
    let result = try resultsOfRunning(
      [
        "swiftc",
        source.platformString,
        "-o", output.platformString,
        "-module-cache-path", moduleCache.platformString,
      ])

    guard result.exitStatus == 0 else {
      throw GYBError.executionFailed(filename: filename, errorOutput: result.stderr)
    }
  }

  /// Runs compiled executable and returns its output.
  private func runCompiledExecutable(_ executable: URL) throws -> String {
    let result = try resultsOfRunning([executable.platformString])

    guard result.exitStatus == 0 else {
      throw GYBError.executionFailed(filename: filename, errorOutput: result.stderr)
    }

    return result.stdout.normalizingLineEndings()
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
    let lineNumber = sourceTemplate.lineNumber(at: index)
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

    let escaped = output.escapedForSwiftMultilineString()
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

extension String {
  /// Returns `self` escaped for Swift multiline string literals, preserving `\(...)` interpolations.
  func escapedForSwiftMultilineString() -> String {
    replacingOccurrences(of: #"\"#, with: #"\\"#)
      .replacingOccurrences(of: #"""""#, with: #"\"\"\""#)
      // Undo escaping for interpolations so \(expr) is undisturbed.
      .replacingOccurrences(of: #"\\("#, with: #"\("#)
  }

  /// Returns `self` with line endings normalized to Unix style (`\n`) for cross-platform consistency.
  ///
  /// On Windows, Swift's print() outputs `\r\n` line endings, but our tests expect `\n`.
  func normalizingLineEndings() -> String {
    replacingOccurrences(of: "\r\n", with: "\n")
  }
}

/// Returns `template`'s `\(file)` and `\(line)` placeholders replaced by `filename` and `line`.
private func formatSourceLocation(_ template: String, filename: String, line: Int) -> String {
  return
    template
    .replacingOccurrences(of: #"\(file)"#, with: filename)
    .replacingOccurrences(of: #"\(line)"#, with: "\(line)")
}
