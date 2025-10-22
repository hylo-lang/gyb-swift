import Foundation

// MARK: - Execution Context

/// Maintains variable bindings, output text, and line directives for executing template code.
struct ExecutionContext {
    /// The accumulated output text.
    var resultText: [Substring] = []
    
    /// Variable bindings available to template code.
    var bindings: [String: Any]
    
    /// Format string for line directives with %(file)s and %(line)d placeholders.
    let lineDirective: String
    
    /// The current template filename.
    let filename: String
    
    /// Current line number in output.
    private var lastEmittedLine: Int = 0
    
    /// Child nodes available to block code via __children__.
    private var children: [ASTNode]?
    
    init(
        filename: String = "stdin",
        lineDirective: String = "//# sourceLocation(file: \"%(file)s\", line: %(line)d)",
        bindings: [String: Any] = [:]
    ) {
        self.filename = filename
        self.lineDirective = lineDirective
        self.bindings = bindings
    }
    
    /// Returns a new context sharing bindings but with __children__ available.
    mutating func createChildContext(children: [ASTNode]) -> ExecutionContext {
        var child = ExecutionContext(
            filename: filename,
            lineDirective: lineDirective,
            bindings: bindings
        )
        child.children = children
        return child
    }
    
    /// Emits a line directive for `line` if needed.
    private mutating func emitLineDirective(_ line: Int) {
        guard !lineDirective.isEmpty && line != lastEmittedLine else { return }
        
        let directive = lineDirective
            .replacingOccurrences(of: "%(file)s", with: filename)
            .replacingOccurrences(of: "%(line)d", with: "\(line)")
        
        resultText.append((directive + "\n")[...])
        lastEmittedLine = line
    }
    
    /// Compiles and executes Swift `code` with access to bindings.
    mutating func executeCode(_ code: Substring, atLine line: Int) throws {
        emitLineDirective(line)
        
        // For __children__ support in block code
        if let children = children {
            let childExecutor = ChildExecutor(children: children, context: self)
            bindings["__children__"] = childExecutor
        }
        
        // In a production implementation, this would:
        // 1. Generate a Swift source file with the code and bindings
        // 2. Compile it using swiftc
        // 3. Execute the resulting binary
        // 4. Capture any output and errors
        //
        // For this translation, we'll use a simplified approach that
        // handles the common patterns in gyb templates.
        
        try executeSwiftCodeDynamically(code, bindings: bindings, context: &self)
    }
    
    /// Returns the result of evaluating Swift `expression`.
    mutating func evaluateExpression(_ expression: Substring, atLine line: Int) throws -> Any {
        emitLineDirective(line)
        return try evaluateSwiftExpression(String(expression), bindings: bindings)
    }
}

/// Allows block code to execute children via __children__[0].execute(__context__).
struct ChildExecutor {
    let children: [ASTNode]
    let context: ExecutionContext
    
    init(children: [ASTNode], context: ExecutionContext) {
        self.children = children
        self.context = context
    }
    
    subscript(index: Int) -> ChildExecutor {
        ChildExecutor(children: [children[index]], context: context)
    }
    
    func execute(_ context: inout ExecutionContext) throws {
        try children.forEach { try $0.execute(&context) }
    }
}

// MARK: - Dynamic Swift Execution

/// Compiles and executes Swift `code` by creating a temporary file, compiling with swiftc, and running it.
private func executeSwiftCodeDynamically(
    _ code: Substring,
    bindings: [String: Any],
    context: inout ExecutionContext
) throws {
    // Create a temporary directory for compilation
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Generate Swift source with bindings
    let bindingsCode = bindings
        .map { "let \($0.key) = \(formatValue($0.value))" }
        .joined(separator: "\n")
    
    let source = """
    import Foundation
    
    // Bindings
    \(bindingsCode)
    
    // User code
    \(code)
    
    """
    
    // Write source file
    let sourceFile = tempDir.appendingPathComponent("main.swift")
    try source.write(to: sourceFile, atomically: true, encoding: .utf8)
    
    // Compile
    let outputFile = tempDir.appendingPathComponent("program")
    let compileProcess = Process()
    compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compileProcess.arguments = [
        sourceFile.path,
        "-o", outputFile.path
    ]
    
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
    if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
        context.resultText.append(output[...])
    }
}

/// Returns the result of evaluating Swift `expression`.
private func evaluateSwiftExpression(
    _ expression: String,
    bindings: [String: Any]
) throws -> Any {
    // Create code that prints the expression result
    let code = "print(\(expression), terminator: \"\")"
    
    var tempContext = ExecutionContext(bindings: bindings)
    try executeSwiftCodeDynamically(code[...], bindings: bindings, context: &tempContext)
    
    return tempContext.resultText.joined()
}

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

