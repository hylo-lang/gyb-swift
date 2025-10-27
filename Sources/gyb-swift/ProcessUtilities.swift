import Foundation

/// Creates a `Process` configured to execute the given command via PATH resolution.
///
/// On Unix-like systems, uses `/usr/bin/env` to resolve the command from PATH.
/// On Windows, uses the command directly.
func processForCommand(_ command: String, arguments: [String]) -> Process {
    let process = Process()

    #if os(Windows)
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
    #else
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
    #endif

    return process
}
