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

/// Creates a `Process` configured to execute the given command via PATH resolution.
///
/// On Unix-like systems, uses `/usr/bin/env` to resolve the command from PATH.
/// On Windows, searches PATH explicitly to find the full executable path.
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

    return process
}
