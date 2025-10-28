import Foundation

#if os(Windows)
  private let isWindows = true
#else
  private let isWindows = false
#endif

#if os(macOS)
  private let isMacOS = true
#else
  private let isMacOS = false
#endif

/// Searches for an executable in PATH on Windows using `where.exe`.
///
/// Returns the full path to the executable, or `nil` if not found.
private func findExecutableInPath(_ command: String) -> String? {
  guard let winDir = ProcessInfo.processInfo.environment["WINDIR"] else {
    return nil
  }

  let whereCommand = (winDir as NSString).appendingPathComponent("System32")
  let whereExe = (whereCommand as NSString).appendingPathComponent("where.exe")

  guard FileManager.default.fileExists(atPath: whereExe) else {
    return nil
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: whereExe)
  process.arguments = [command]

  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = Pipe()

  do {
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
      // where.exe returns the first match on the first line
      return output.split(separator: "\n", maxSplits: 1).first.map {
        String($0).trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
  } catch {
    return nil
  }

  return nil
}

/// The SDK root path for macOS, or `nil` if not on macOS or unable to determine.
private func sdkRootPath() -> String? {
  guard isMacOS else { return nil }

  let xcrunProcess = Process()
  xcrunProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  xcrunProcess.arguments = ["--show-sdk-path"]

  let pipe = Pipe()
  xcrunProcess.standardOutput = pipe
  xcrunProcess.standardError = Pipe()

  do {
    try xcrunProcess.run()
    xcrunProcess.waitUntilExit()

    guard xcrunProcess.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(
      in: .whitespacesAndNewlines),
      !path.isEmpty
    {
      return path
    }
  } catch {
    return nil
  }

  return nil
}

/// Creates a `Process` configured to execute the given command via PATH resolution.
///
/// On Unix-like systems, uses `/usr/bin/env` to resolve the command from PATH.
/// On Windows, searches PATH explicitly to find the full executable path.
/// On macOS, sets SDKROOT environment variable if not already set.
func processForCommand(_ command: String, arguments: [String]) -> Process {
  let process = Process()

  if isWindows {
    // On Windows, search PATH explicitly to avoid looking in current directory
    if let executablePath = findExecutableInPath(command) {
      process.executableURL = URL(fileURLWithPath: executablePath)
    } else {
      // Fall back to command as-is if not found in PATH
      process.executableURL = URL(fileURLWithPath: command)
    }
    process.arguments = arguments
  } else {
    // On Unix-like systems, use /usr/bin/env which searches PATH safely
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments
  }

  // On macOS, ensure SDKROOT is set for Swift compilation
  if isMacOS {
    var environment = ProcessInfo.processInfo.environment
    if environment["SDKROOT"] == nil, let sdkRoot = sdkRootPath() {
      environment["SDKROOT"] = sdkRoot
      process.environment = environment
    }
  }

  return process
}
