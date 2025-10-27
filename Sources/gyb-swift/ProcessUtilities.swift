import Foundation

/// Searches for an executable in PATH.
///
/// Returns the full path to the executable, or `nil` if not found.
private func findExecutableInPath(_ command: String) -> String? {
    guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
        return nil
    }

    #if os(Windows)
        let pathSeparator = ";"
        let pathExtensions =
            (ProcessInfo.processInfo.environment["PATHEXT"] ?? ".COM;.EXE;.BAT;.CMD")
            .split(separator: ";")
            .map { String($0) }
    #else
        let pathSeparator = ":"
        let pathExtensions = [""]
    #endif

    let searchPaths = pathEnv.split(separator: Character(pathSeparator)).map { String($0) }

    for searchPath in searchPaths {
        for ext in pathExtensions {
            let candidatePath = (searchPath as NSString).appendingPathComponent(command + ext)
            if FileManager.default.isExecutableFile(atPath: candidatePath) {
                return candidatePath
            }
        }
    }

    return nil
}

/// The SDK root path for macOS, or `nil` if not on macOS or unable to determine.
private func sdkRootPath() -> String? {
    #if os(macOS)
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
    #endif

    return nil
}

/// Creates a `Process` configured to execute the given command via PATH resolution.
///
/// On Unix-like systems, uses `/usr/bin/env` to resolve the command from PATH.
/// On Windows, searches PATH explicitly to find the full executable path.
/// On macOS, sets SDKROOT environment variable if not already set.
func processForCommand(_ command: String, arguments: [String]) -> Process {
    let process = Process()

    #if os(Windows)
        // On Windows, search PATH explicitly to avoid looking in current directory
        if let executablePath = findExecutableInPath(command) {
            process.executableURL = URL(fileURLWithPath: executablePath)
        } else {
            // Fall back to command as-is if not found in PATH
            process.executableURL = URL(fileURLWithPath: command)
        }
        process.arguments = arguments
    #else
        // On Unix-like systems, use /usr/bin/env which searches PATH safely
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
    #endif

    // On macOS, ensure SDKROOT is set for Swift compilation
    #if os(macOS)
        var environment = ProcessInfo.processInfo.environment
        if environment["SDKROOT"] == nil, let sdkRoot = sdkRootPath() {
            environment["SDKROOT"] = sdkRoot
            process.environment = environment
        }
    #endif

    return process
}
