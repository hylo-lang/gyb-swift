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

// MARK: - Swift Script Runner

/// Runs Swift code using the interpreter or compiler.
struct SwiftScriptRunner {
  /// Source filename for error reporting.
  let filename: String

  init(filename: String) {
    self.filename = filename
  }

  /// Executes `swiftCode` using Swift interpreter or compilation.
  ///
  /// By default, uses the Swift interpreter on non-Windows platforms for faster execution.
  /// On Windows or when `forceCompilation` is true, compiles and runs the generated code.
  func execute(_ swiftCode: String, forceCompilation: Bool = false) throws -> String {
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
}

extension String {
  /// Returns `self` with line endings normalized to Unix style (`\n`) for cross-platform consistency.
  ///
  /// On Windows, Swift's print() outputs `\r\n` line endings, but our tests expect `\n`.
  fileprivate func normalizingLineEndings() -> String {
    replacingOccurrences(of: "\r\n", with: "\n")
  }
}
