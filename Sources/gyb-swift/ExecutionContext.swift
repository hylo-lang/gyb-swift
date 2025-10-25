import Foundation

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

/// Converts an array of AST nodes to Swift code.
/// Batches consecutive literals and substitutions into print statements.
/// Code nodes are emitted directly - Swift's compiler handles the nesting.
func astNodesToSwiftCode(
    _ nodes: [ASTNode],
    filename: String = "",
    lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))",
    emitSourceLocation: Bool = true
) -> String {
    var result: [String] = []
    var textBatch: [String] = []  // Accumulate literal text with \() interpolations
    var textBatchLine: Int?  // Line number for pending text batch
    
    func flushTextBatch() {
        guard !textBatch.isEmpty else { return }
        let combined = textBatch.joined()
        if !combined.isEmpty {
            // Emit source location before the print statement
            if emitSourceLocation, let line = textBatchLine, !filename.isEmpty {
                let directive = lineDirective
                    .replacingOccurrences(of: "\\(file)", with: filename)
                    .replacingOccurrences(of: "\\(line)", with: "\(line)")
                result.append(directive)
            }
            
            // Escape """ and \ for multiline string literal
            let content = combined
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
                // Unescape our interpolation markers back to single backslash
                .replacingOccurrences(of: "\\\\(", with: "\\(")
            
            result.append("print(\"\"\"\n\(content)\n\"\"\", terminator: \"\")")
        }
        textBatch.removeAll()
        textBatchLine = nil
    }
    
    for node in nodes {
        switch node {
        case let literal as LiteralNode:
            // Track line number for first node in batch
            if textBatchLine == nil {
                textBatchLine = literal.line
            }
            // Add to text batch - will be escaped later
            textBatch.append(String(literal.text))
            
        case let substitution as SubstitutionNode:
            // Track line number for first node in batch
            if textBatchLine == nil {
                textBatchLine = substitution.line
            }
            // Add interpolation to text batch (with \\( to survive first escaping pass)
            textBatch.append("\\(\(substitution.expression))")
            
        case let code as CodeNode:
            // Flush any pending text, then emit code directly
            flushTextBatch()
            result.append(String(code.code))
            
        default:
            break
        }
    }
    
    flushTextBatch()
    return result.filter { !$0.isEmpty }.joined(separator: "\n")
}

// MARK: - Template Execution

/// Returns the generated Swift source code for `ast` with `bindings` (without executing).
func generateSwiftCode(
    _ ast: BlockNode,
    bindings: [String: Any] = [:],
    filename: String = "",
    lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))",
    emitSourceLocation: Bool = true
) throws -> String {
    // Generate complete Swift program
    let bindingsCode = bindings
        .filter { $0.key != "__children__" && $0.key != "__context__" }  // Filter internal bindings
        .map { "let \($0.key) = \(formatValue($0.value))" }
        .joined(separator: "\n")
    
    let swiftCode = astNodesToSwiftCode(
        ast.children,
        filename: filename,
        lineDirective: lineDirective,
        emitSourceLocation: emitSourceLocation
    )
    
    return """
    import Foundation
    
    // Bindings
    \(bindingsCode)
    
    // Generated code
    \(swiftCode)
    
    """
}

/// Formats a Swift value for embedding in generated code.
private func formatValue(_ value: Any) -> String {
    switch value {
    case let str as String:
        // Escape quotes and backslashes
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    case let num as Int:
        return "\(num)"
    case let num as Double:
        return "\(num)"
    case let bool as Bool:
        return "\(bool)"
    case let array as [Any]:
        let elements = array.map { formatValue($0) }.joined(separator: ", ")
        return "[\(elements)]"
    default:
        return "\"\(value)\""
    }
}

/// Executes `ast` with `bindings` and returns generated output.
func executeTemplate(
    _ ast: BlockNode,
    filename: String = "",
    lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))",
    bindings: [String: Any] = [:]
) throws -> String {
    return try executeTemplateAsWholeProgram(
        ast,
        filename: filename,
        lineDirective: lineDirective,
        bindings: bindings
    )
}

/// Executes template by compiling and running generated Swift code.
private func executeTemplateAsWholeProgram(
    _ ast: BlockNode,
    filename: String,
    lineDirective: String,
    bindings: [String: Any]
) throws -> String {
    // Generate complete Swift program
    let swiftCode = try generateSwiftCode(
        ast,
        bindings: bindings,
        filename: filename,
        lineDirective: lineDirective,
        emitSourceLocation: false  // Don't emit line directives for execution
    )
    
    // Write to temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let sourceFile = tempDir.appendingPathComponent("gyb_\(UUID().uuidString).swift")
    let executableFile = tempDir.appendingPathComponent("gyb_\(UUID().uuidString)")
    
    defer {
        try? FileManager.default.removeItem(at: sourceFile)
        try? FileManager.default.removeItem(at: executableFile)
    }
    
    try swiftCode.write(to: sourceFile, atomically: true, encoding: .utf8)
    
    // Compile
    let compileProcess = Process()
    compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compileProcess.arguments = ["-o", executableFile.path, sourceFile.path]
    
    let compileErrorPipe = Pipe()
    compileProcess.standardError = compileErrorPipe
    compileProcess.standardOutput = compileErrorPipe
    
    try compileProcess.run()
    compileProcess.waitUntilExit()
    
    if compileProcess.terminationStatus != 0 {
        let errorData = compileErrorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown compilation error"
        throw GYBError.compilationFailed(errorMessage)
    }
    
    // Execute
    let runProcess = Process()
    runProcess.executableURL = executableFile
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    runProcess.standardOutput = outputPipe
    runProcess.standardError = errorPipe
    
    try runProcess.run()
    runProcess.waitUntilExit()
    
    if runProcess.terminationStatus != 0 {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown execution error"
        throw GYBError.executionFailed(errorMessage)
    }
    
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: outputData, encoding: .utf8) ?? ""
}
