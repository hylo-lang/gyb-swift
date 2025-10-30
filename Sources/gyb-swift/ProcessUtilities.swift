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

/// Returns the standard output from running `commandLine` passing
/// `arguments`, trimmed of whitespace.
///
/// If `commandLine` contains no path separators, it is looked up in `PATH`.
///
/// - Parameter setSKDRoot: true iff xcrun should be used to set the SDKROOT
///   environment variable for the process.
private func standardOutputOf(
  _ commandLine: [String], setSDKRoot: Bool = true
) throws -> String {
  let result = try resultsOfRunning(commandLine, setSDKRoot: setSDKRoot)

  guard result.exitStatus == 0 else {
    throw Failure("\(commandLine) exited with \(result.exitStatus)")
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

  let output = try standardOutputOf([whereExe, command])

  // where.exe returns the first match on the first line
  guard let r = output.split(separator: "\n", maxSplits: 1).first else {
    throw Failure("output of \(whereExe) is empty.")
  }
  return String(r)
}

/// The value to set for SDKROOT in subprocess environments on macOS.
internal let swiftSDKRoot: String =
  if isMacOS {
    ProcessInfo.processInfo.environment["SDKROOT"]
      ?? { () -> String in
        do {
          // Don't set SDKROOT in the environment to avoid infinite recursion.
          return try standardOutputOf(
            ["/usr/bin/xcrun", "--show-sdk-path"], setSDKRoot: false)
        } catch let e {
          fatalError("\(e)")
        }
      }()
  } else {
    "UNUSED"
  }

/// The SDK root path on macOS.
///
/// - Precondition: running on macOS
private func sdkRootPath() throws -> String {
  precondition(isMacOS)
  let path = try standardOutputOf(["/usr/bin/xcrun", "--show-sdk-path"])
  if path.isEmpty { throw Failure("'xcrun --show-sdk-path' returned empty string") }
  return path
}

/// Output from running a process.
struct ProcessResults {
  /// Standard output as UTF-8 string.
  let stdout: String
  /// Standard error as UTF-8 string.
  let stderr: String
  /// Process exit status.
  let exitStatus: Int32
}

/// Returns the result of running `command` passing `arguments`.
///
/// If `commandLine[0]` contains no path separators, the executable is
/// looked up in `PATH`.
///
/// - Parameter setSKDRoot: true iff xcrun should be used to set the SDKROOT
///   environment variable for the process.
func resultsOfRunning(_ commandLine: [String], setSDKRoot: Bool = true) throws -> ProcessResults {
  let p = Process()

  let command = commandLine.first!
  var arguments = Array(commandLine.dropFirst())

  // If executable contains path separators, use it directly without PATH search
  if command.contains(isWindows ? "\\" : "/") {
    p.executableURL = URL(fileURLWithPath: command)
  } else {
    if isWindows {
      p.executableURL = URL(fileURLWithPath: try findWindowsExecutableInPath(command))
    } else {
      // Let env find and run the executable.
      p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      arguments.insert(command, at: 0)
    }
  }
  p.arguments = Array(arguments)

  if setSDKRoot && isMacOS {
    var e = ProcessInfo.processInfo.environment
    e["SDKROOT"] = swiftSDKRoot
    p.environment = e
  }

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  p.standardOutput = stdoutPipe
  p.standardError = stderrPipe

  do {
    try p.run()
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

  p.waitUntilExit()

  // Retrieve the data (blocks until background reads complete)
  let stdout = try stdoutData().asUTF8(source: "\(command) stdout")
  let stderr = try stderrData().asUTF8(source: "\(command) stderr")

  return ProcessResults(
    stdout: stdout,
    stderr: stderr,
    exitStatus: p.terminationStatus
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

extension Data {
  /// `self` decoded as UTF-8.
  func asUTF8(source: String) throws -> String {
    guard let result = String(data: self, encoding: .utf8) else {
      throw Failure("\(source) not UTF-8 encoded")
    }
    return result
  }
}
