import Foundation

#if os(Windows)
  internal let isWindows = true
#else
  internal let isWindows = false
#endif

#if os(macOS)
  internal let isMacOS = true
#else
  internal let isMacOS = false
#endif

/// The environment variables of the running process.
///
/// On platforms where environment variable names are case-insensitive (Windows), the keys have
/// all been normalized to upper case, so looking up a variable value from this dictionary by a
/// name that isn't all-uppercase is a non-portable operation.
private let environmentVariables = isWindows
  ? Dictionary(
    uniqueKeysWithValues: ProcessInfo.processInfo.environment.lazy.map {
      (key: $0.key.uppercased(), value: $0.value)
    })
  : ProcessInfo.processInfo.environment

/// Runs `executable` with `arguments`, returning stdout trimmed of whitespace.
///
/// Returns `nil` if the process fails or produces no output.
private func runProcessForOutput(
  _ executable: String, arguments: [String]
) throws -> String {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: executable)
  p.arguments = arguments

  let output = Pipe()
  p.standardOutput = output
  p.standardError = Pipe()

  do {
    try p.run()
  }
  catch let e {
    throw Failure("running \(executable) \(arguments) threw.", e)
  }

  p.waitUntilExit()

  guard p.terminationStatus == 0 else {
    throw Failure("\(executable) \(arguments) exited with \(p.terminationStatus)")
  }

  guard let output = String(
          data: output.fileHandleForReading.readDataToEndOfFile(),
          encoding: .utf8) else {
    throw Failure("output of \(executable) \(arguments) not UTF-8 encoded")
  }

  return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Failure: Error {
  let reason: String
  let error: (any Error)?
  init(_ reason: String, _ error: (any Error)? = nil) {
    self.reason = reason
    self.error = error
  }
}

/// Searches for an executable in PATH on Windows using `where.exe`.
///
/// Returns the full path to the executable.
private func findWindowsExecutableInPath(_ command: String) throws -> String {
  guard let winDir = environmentVariables["WINDIR"] else {
    throw Failure("No WINDIR in environment")
  }

  let whereCommand = (winDir as NSString).appendingPathComponent("System32")
  let whereExe = (whereCommand as NSString).appendingPathComponent("where.exe")

  guard FileManager.default.fileExists(atPath: whereExe) else {
    throw Failure("\(whereExe) doesn't exist")
  }

  let output = try runProcessForOutput(whereExe, arguments: [command])

  // where.exe returns the first match on the first line
  guard let r = output.split(separator: "\n", maxSplits: 1).first else {
    throw Failure("output of \(whereExe) is empty.")
  }
  return String(r)
}

/// The SDK root path on macOS.
///
/// - Precondition: running on macOS
private func sdkRootPath() throws -> String {
  precondition(isMacOS)
  let path = try runProcessForOutput("/usr/bin/xcrun", arguments: ["--show-sdk-path"])
  if path.isEmpty { throw Failure("'xcrun --show-sdk-path' returned empty string") }
  return path
}

/// Creates a `Process` configured to execute the given command via PATH resolution.
///
/// On Unix-like systems, uses `/usr/bin/env` to resolve the command from PATH.
/// On Windows, searches PATH explicitly to find the full executable path.
/// On macOS, sets SDKROOT environment variable if not already set.
func processForCommand(_ command: String, arguments: [String]) throws -> Process {
  let p = Process()

  if isWindows {
    // On Windows, search PATH explicitly to avoid looking in current directory
    let executablePath = try findWindowsExecutableInPath(command)
    p.executableURL = URL(fileURLWithPath: executablePath)
    p.arguments = arguments
  } else {
    // On Unix-like systems, use /usr/bin/env which searches PATH safely
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = [command] + arguments
  }

  // On macOS, ensure SDKROOT is set for Swift compilation
  if isMacOS {
    var environment = ProcessInfo.processInfo.environment
    if environment["SDKROOT"] == nil {
      environment["SDKROOT"] = try sdkRootPath()
      p.environment = environment
    }
  }

  return p
}
