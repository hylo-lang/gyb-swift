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
private func runProcessForOutput(
  _ executable: String, arguments: [String]
) throws -> String {
  let result = try runProcess(executable, arguments: arguments)

  guard result.exitStatus == 0 else {
    throw Failure("\(executable) \(arguments) exited with \(result.exitStatus)")
  }

  return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Failure: Error, CustomStringConvertible {
  let reason: String
  let error: (any Error)?

  init(_ reason: String, _ error: (any Error)? = nil) {
    self.reason = reason
    self.error = error
  }

  var description: String {
    if let error = error {
      return "\(reason): \(error)"
    }
    return reason
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

  // Set SDKROOT on macOS if needed, but skip for xcrun itself to prevent infinite recursion
  let isXcrun = command.hasSuffix("/xcrun") || command == "xcrun"
  if isMacOS && !isXcrun {
    var environment = ProcessInfo.processInfo.environment
    if environment["SDKROOT"] == nil {
      environment["SDKROOT"] = try sdkRootPath()
      p.environment = environment
    }
  }

  return p
}

/// Output from running a process.
struct ProcessOutput {
  /// Standard output as UTF-8 string.
  let stdout: String
  /// Standard error as UTF-8 string.
  let stderr: String
  /// Process exit status.
  let exitStatus: Int32
}

/// Runs `command` with `arguments`, returning captured output and exit status.
func runProcess(_ command: String, arguments: [String]) throws -> ProcessOutput {
  let process = try processForCommand(command, arguments: arguments)

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  do {
    try process.run()
  } catch {
    let commandLine =
      arguments.isEmpty
      ? command
      : "\(command) \(arguments.joined(separator: " "))"
    throw Failure("Failed to run '\(commandLine)'", error)
  }

  // Read pipes on background threads to prevent deadlock if output exceeds pipe buffer size.
  // The child process will block if pipe buffers fill up, so we must drain them continuously.
  let stdoutData = readPipeInBackground(stdoutPipe)
  let stderrData = readPipeInBackground(stderrPipe)

  process.waitUntilExit()

  // Retrieve the data (blocks until background reads complete)
  let stdout = try decodeUTF8(stdoutData(), as: "\(command) stdout")
  let stderr = try decodeUTF8(stderrData(), as: "\(command) stderr")

  return ProcessOutput(
    stdout: stdout,
    stderr: stderr,
    exitStatus: process.terminationStatus
  )
}

/// Starts reading all data from `pipe` using event-driven I/O.
///
/// Returns a closure that blocks until reading completes and returns the data.
/// This prevents pipe buffer deadlocks by draining pipes while the process runs.
/// Uses non-blocking I/O with readability handlers for efficiency.
private func readPipeInBackground(_ pipe: Pipe) -> () -> Data {
  // Box to safely share mutable state across concurrency boundary
  final class DataBox: @unchecked Sendable {
    var data = Data()
  }
  let box = DataBox()
  let group = DispatchGroup()

  group.enter()
  pipe.fileHandleForReading.readabilityHandler = { handle in
    let chunk = handle.availableData
    if chunk.isEmpty {  // EOF on the pipe
      pipe.fileHandleForReading.readabilityHandler = nil
      group.leave()
    } else {
      box.data.append(chunk)
    }
  }

  return {
    group.wait()
    return box.data
  }
}

/// Decodes `data` as UTF-8, throwing `Failure` with `source` name if it fails.
private func decodeUTF8(_ data: Data, as source: String) throws -> String {
  guard let result = String(data: data, encoding: .utf8) else {
    throw Failure("\(source) not UTF-8 encoded")
  }
  return result
}
