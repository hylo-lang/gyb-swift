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
private let environmentVariables =
  isWindows
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
  } catch let e {
    throw Failure("running \(executable) \(arguments) threw.", e)
  }

  p.waitUntilExit()

  guard p.terminationStatus == 0 else {
    throw Failure("\(executable) \(arguments) exited with \(p.terminationStatus)")
  }

  guard
    let output = String(
      data: output.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8)
  else {
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

/// Returns a `Process` that runs `command` with the given `arguments`.
///
/// If `command` contains no path separators, it will be found in
/// `PATH`.  On macOS, ensures SDKROOT is set in the environment in
/// case the command needs it.
func processForCommand(_ command: String, arguments: [String]) throws -> Process {
  let p = Process()

  p.arguments = arguments
  // If command contains path separators, use it directly without PATH search
  if command.contains(isWindows ? "\\" : "/") {
    p.executableURL = URL(fileURLWithPath: command)
  } else {
    if isWindows {
      p.executableURL = URL(fileURLWithPath: try findWindowsExecutableInPath(command))
    } else {
      // Let env find and run the executable.
      p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      p.arguments = [command] + arguments
    }
  }

  if isMacOS {
    var environment = ProcessInfo.processInfo.environment
    if environment["SDKROOT"] == nil {
      environment["SDKROOT"] = try sdkRootPath()
      p.environment = environment
    }
  }

  return p
}
