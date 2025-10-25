import Foundation
import Algorithms

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

/// Returns the source location index for generating line directives.
/// - Parameter nodes: Nodes to examine for source location
/// - Returns: The index into the template text, if available
private func sourceLocationIndex(for nodes: [ASTNode]) -> String.Index? {
    guard let first = nodes.first else { return nil }
    
    if let literal = first as? LiteralNode {
        return literal.text.startIndex
    } else if let substitution = first as? SubstitutionNode {
        return substitution.expression.startIndex
    }
    return nil
}

/// Returns the text content from template output nodes.
/// - Parameter nodes: Literal and substitution nodes to convert to text
/// - Returns: Array of text strings with interpolations marked
private func textContent(from nodes: [ASTNode]) -> [String] {
    return nodes.compactMap { node in
        switch node {
        case let literal as LiteralNode:
            return String(literal.text)
        case let substitution as SubstitutionNode:
            return "\\(\(substitution.expression))"
        default:
            return nil
        }
    }
}

/// Returns text escaped for use in Swift multiline string literals.
/// - Parameter text: Raw text to escape
/// - Returns: Text with backslashes, triple-quotes escaped, and interpolation markers preserved
private func escapeForSwiftMultilineString(_ text: String) -> String {
    return text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
        .replacingOccurrences(of: "\\\\(", with: "\\(")
}

/// Formats a source location directive by substituting file and line placeholders.
/// - Parameters:
///   - template: Line directive template with \(file) and \(line) placeholders
///   - filename: Source filename to substitute
///   - line: Line number to substitute
/// - Returns: Formatted source location directive
private func formatSourceLocation(_ template: String, filename: String, line: Int) -> String {
    return template
        .replacingOccurrences(of: "\\(file)", with: filename)
        .replacingOccurrences(of: "\\(line)", with: "\(line)")
}

/// Returns a Swift print statement for template output nodes.
/// - Parameters:
///   - nodes: Literal and substitution nodes to emit as output
///   - templateText: Original template text for line number computation
///   - lineStarts: Pre-computed line start indices
///   - filename: Source filename for line directives
///   - lineDirective: Line directive format template
///   - emitSourceLocation: Whether to include source location directives
/// - Returns: Swift print statement with optional source location directive, or nil if nodes produce no output
private func printStatement(
    for nodes: [ASTNode],
    templateText: String,
    lineStarts: [String.Index],
    filename: String,
    lineDirective: String,
    emitSourceLocation: Bool
) -> String? {
    guard !nodes.isEmpty else { return nil }
    
    let parts = textContent(from: nodes)
    guard !parts.isEmpty else { return nil }
    
    let combined = parts.joined()
    guard !combined.isEmpty else { return nil }
    
    var result: [String] = []
    
    // Emit source location directive if requested
    if emitSourceLocation, !filename.isEmpty, let index = sourceLocationIndex(for: nodes) {
        let lineNumber = getLineNumber(for: index, in: templateText, lineStarts: lineStarts)
        let directive = formatSourceLocation(lineDirective, filename: filename, line: lineNumber)
        result.append(directive)
    }
    
    let escaped = escapeForSwiftMultilineString(combined)
    result.append("print(\"\"\"\n\(escaped)\n\"\"\", terminator: \"\")")
    
    return result.joined(separator: "\n")
}

/// Returns whether a node represents template output (literal text or substitution).
/// - Parameter node: Node to examine
/// - Returns: true if node is a literal or substitution
private func isOutputNode(_ node: ASTNode) -> Bool {
    return node is LiteralNode || node is SubstitutionNode
}

/// Converts an array of AST nodes to Swift code.
/// - Parameters:
///   - nodes: Template AST nodes to convert
///   - templateText: Original template text for line number computation
///   - filename: Source filename for line directives
///   - lineDirective: Line directive format template with \(file) and \(line) placeholders
///   - emitSourceLocation: Whether to include source location directives
/// - Returns: Swift source code as a string
func astNodesToSwiftCode(
    _ nodes: [ASTNode],
    templateText: String = "",
    filename: String = "",
    lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))",
    emitSourceLocation: Bool = true
) -> String {
    let lineStarts = !templateText.isEmpty ? getLineStarts(templateText) : []
    
    // Group consecutive output nodes together; keep code nodes separate
    let chunks = nodes.chunked { prev, curr in
        isOutputNode(prev) && isOutputNode(curr)
    }
    
    let lines = chunks.compactMap { chunk -> String? in
        let chunkArray = Array(chunk)
        
        // Code nodes are emitted directly
        if let code = chunkArray.first as? CodeNode {
            return String(code.code)
        }
        
        // Output nodes are batched into print statements
        return printStatement(
            for: chunkArray,
            templateText: templateText,
            lineStarts: lineStarts,
            filename: filename,
            lineDirective: lineDirective,
            emitSourceLocation: emitSourceLocation
        )
    }
    
    return lines.filter { !$0.isEmpty }.joined(separator: "\n")
}

// MARK: - Template Execution

/// Returns the generated Swift source code for `ast` with `bindings` (without executing).
func generateSwiftCode(
    _ ast: BlockNode,
    templateText: String,
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
        templateText: templateText,
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
    templateText: String,
    filename: String = "",
    lineDirective: String = "#sourceLocation(file: \"\\(file)\", line: \\(line))",
    bindings: [String: Any] = [:]
) throws -> String {
    return try executeTemplateAsWholeProgram(
        ast,
        templateText: templateText,
        filename: filename,
        lineDirective: lineDirective,
        bindings: bindings
    )
}

/// Executes template by compiling and running generated Swift code.
private func executeTemplateAsWholeProgram(
    _ ast: BlockNode,
    templateText text: String,
    filename: String,
    lineDirective: String,
    bindings: [String: Any]
) throws -> String {
    // Generate complete Swift program
    let swiftCode = try generateSwiftCode(
        ast,
        templateText: text,
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
