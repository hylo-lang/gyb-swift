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

/// Converts an array of AST nodes to Swift code, batching literals and substitutions into multiline strings.
func astNodesToSwiftCode(_ nodes: [ASTNode], indent: String = "", filename: String = "", lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))", emitSourceLocation: Bool = true) -> String {
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
                result.append(indent + directive)
            }
            
            // Escape """ and \ for multiline string literal
            var content = combined
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
                // Unescape our interpolation markers back to single backslash
                .replacingOccurrences(of: "\\\\(", with: "\\(")
            
            // Indent each line to match closing delimiter
            if !indent.isEmpty {
                content = content.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { indent + $0 }
                    .joined(separator: "\n")
            }
            
            result.append(indent + "print(\"\"\"\n\(content)\n\(indent)\"\"\", terminator: \"\")")
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
            
        case let subst as SubstitutionNode:
            // Track line number for first node in batch
            if textBatchLine == nil {
                textBatchLine = subst.line
            }
            // Add as interpolation - use double backslash temporarily, will be fixed in flush
            textBatch.append("\\(\(subst.expression))")
            
        case let code as CodeNode:
            // Flush any pending text, then emit code (no source location - may be mid-statement)
            flushTextBatch()
            result.append(indent + String(code.code))
            
        case let block as BlockNode:
            if let code = block.code {
                // Flush pending text, emit control flow (no source location - may be mid-statement)
                flushTextBatch()
                result.append(indent + String(code))
                result.append(astNodesToSwiftCode(block.children, indent: indent + "    ", filename: filename, lineDirective: lineDirective, emitSourceLocation: emitSourceLocation))
                
                // Add closing brace if code has unmatched {
                let openBraces = code.filter { $0 == "{" }.count
                let closeBraces = code.filter { $0 == "}" }.count
                if openBraces > closeBraces {
                    result.append(indent + "}")
                }
            } else {
                // Simple sequence - process children inline
                result.append(astNodesToSwiftCode(block.children, indent: indent, filename: filename, lineDirective: lineDirective, emitSourceLocation: emitSourceLocation))
            }
            
        default:
            break
        }
    }
    
    flushTextBatch()
    return result.filter { !$0.isEmpty }.joined(separator: "\n")
}

/// Converts an AST node to executable Swift code.
func astNodeToSwiftCode(_ node: ASTNode, indent: String = "", filename: String = "", lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))", emitSourceLocation: Bool = true) -> String {
    if let block = node as? BlockNode {
        return astNodesToSwiftCode(block.children, indent: indent, filename: filename, lineDirective: lineDirective, emitSourceLocation: emitSourceLocation)
    } else {
        return astNodesToSwiftCode([node], indent: indent, filename: filename, lineDirective: lineDirective, emitSourceLocation: emitSourceLocation)
    }
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
    
    let swiftCode = astNodeToSwiftCode(ast, filename: filename, lineDirective: lineDirective, emitSourceLocation: emitSourceLocation)
    
    return """
    import Foundation
    
    // Bindings
    \(bindingsCode)
    
    // Generated code
    \(swiftCode)
    
    """
}

/// Returns the generated text from executing `ast` with `bindings`.
func executeTemplate(
    _ ast: BlockNode,
    filename: String = "stdin",
    lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))",
    bindings: [String: Any] = [:]
) throws -> String {
    // Use whole-program compilation (supports control flow)
    return try executeTemplateAsWholeProgram(ast, bindings: bindings, filename: filename, lineDirective: lineDirective)
}

/// Executes template by converting entire AST to one Swift program.
// This approach supports control flow (% for, % if) which node-by-node can't handle.
private func executeTemplateAsWholeProgram(
    _ ast: BlockNode,
    bindings: [String: Any],
    filename: String = "",
    lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))"
) throws -> String {
    // Generate complete Swift program
    let bindingsCode = bindings
        .filter { $0.key != "__children__" && $0.key != "__context__" }  // Filter internal bindings
        .map { "let \($0.key) = \(formatValue($0.value))" }
        .joined(separator: "\n")
    
    let swiftCode = astNodeToSwiftCode(ast, filename: filename, lineDirective: lineDirective, emitSourceLocation: !filename.isEmpty)
    
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

