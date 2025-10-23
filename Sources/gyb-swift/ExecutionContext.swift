import Foundation

/// Returns Swift source code representation of `value`.
private func formatValue(_ value: Any) -> String {
    switch value {
    case let s as String:
        return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    case let i as Int:
        return "\(i)"
    case let d as Double:
        return "\(d)"
    case let b as Bool:
        return "\(b)"
    case let arr as [Any]:
        let elements = arr.map { formatValue($0) }.joined(separator: ", ")
        return "[\(elements)]"
    default:
        return "\(value)"
    }
}

// MARK: - Errors

/// Errors that can occur during template execution.
enum GYBError: Error, CustomStringConvertible {
    case compilationFailed(String)
    case executionFailed(String)
    case parseError(String)
    
    var description: String {
        switch self {
        case .compilationFailed(let message):
            return "Compilation failed: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

// MARK: - AST to Swift Code Conversion

/// Converts an AST node to executable Swift code.
// Literal nodes → print() statements
// Code nodes (% lines) → literal Swift code  
// Substitution nodes (${expr}) → print(expr, terminator: "")
func astNodeToSwiftCode(_ node: ASTNode, indent: String = "") -> String {
    switch node {
    case let literal as LiteralNode:
        // Escape for Swift string literal
        let escaped = literal.text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
        return indent + "print(\"\(escaped)\", terminator: \"\")"
        
    case let code as CodeNode:
        // % lines are literal Swift code
        return indent + code.code
        
    case let subst as SubstitutionNode:
        // ${expr} → print(expr, terminator: "")
        return indent + "print(\(subst.expression), terminator: \"\")"
        
    case let block as BlockNode:
        if let code = block.code {
            // Block with control code (wraps children)
            var result = indent + code + "\n"
            result += block.children.map { astNodeToSwiftCode($0, indent: indent + "    ") }.joined(separator: "\n")
            // Add closing brace if code has unmatched {
            let openBraces = code.filter { $0 == "{" }.count
            let closeBraces = code.filter { $0 == "}" }.count
            if openBraces > closeBraces {
                result += "\n" + indent + "}"
            }
            return result
        } else {
            // Simple sequence
            return block.children.map { astNodeToSwiftCode($0, indent: indent) }.joined(separator: "\n")
        }
        
    default:
        return ""
    }
}

// MARK: - Template Execution

/// Returns the generated text from executing `ast` with `bindings`.
func executeTemplate(
    _ ast: BlockNode,
    filename: String = "stdin",
    lineDirective: String = "//# sourceLocation(file: \"%(file)s\", line: %(line)d)",
    bindings: [String: Any] = [:]
) throws -> String {
    // Use whole-program compilation (supports control flow)
    return try executeTemplateAsWholeProgram(ast, bindings: bindings)
}

/// Executes template by converting entire AST to one Swift program.
// This approach supports control flow (% for, % if) which node-by-node can't handle.
private func executeTemplateAsWholeProgram(
    _ ast: BlockNode,
    bindings: [String: Any]
) throws -> String {
    // Generate complete Swift program
    let bindingsCode = bindings
        .filter { $0.key != "__children__" && $0.key != "__context__" }  // Filter internal bindings
        .map { "let \($0.key) = \(formatValue($0.value))" }
        .joined(separator: "\n")
    
    let swiftCode = astNodeToSwiftCode(ast)
    
    let source = """
    import Foundation
    
    // Bindings
    \(bindingsCode)
    
    // Generated code
    \(swiftCode)
    
    """
    
    // Compile and execute
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    let sourceFile = tempDir.appendingPathComponent("main.swift")
    try source.write(to: sourceFile, atomically: true, encoding: .utf8)
    
    // Compile
    let outputFile = tempDir.appendingPathComponent("program")
    let compileProcess = Process()
    compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compileProcess.arguments = [sourceFile.path, "-o", outputFile.path]
    
    let errorPipe = Pipe()
    compileProcess.standardError = errorPipe
    
    try compileProcess.run()
    compileProcess.waitUntilExit()
    
    guard compileProcess.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
        throw GYBError.compilationFailed(errorMessage)
    }
    
    // Execute
    let runProcess = Process()
    runProcess.executableURL = outputFile
    
    let outputPipe = Pipe()
    runProcess.standardOutput = outputPipe
    
    try runProcess.run()
    runProcess.waitUntilExit()
    
    // Capture output
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: outputData, encoding: .utf8) ?? ""
}

