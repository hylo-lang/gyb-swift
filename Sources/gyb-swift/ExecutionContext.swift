import Foundation

// MARK: - Execution Context

/// Maintains variable bindings, output text, and line directives for executing template code.
class ExecutionContext {
    /// The accumulated output text.
    var resultText: [String] = []
    
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
    func createChildContext(children: [ASTNode]) -> ExecutionContext {
        let child = ExecutionContext(
            filename: filename,
            lineDirective: lineDirective,
            bindings: bindings
        )
        child.children = children
        return child
    }
    
    /// Emits a line directive for `line` if needed.
    private func emitLineDirective(_ line: Int) {
        guard !lineDirective.isEmpty && line != lastEmittedLine else { return }
        
        let directive = lineDirective
            .replacingOccurrences(of: "%(file)s", with: filename)
            .replacingOccurrences(of: "%(line)d", with: "\(line)")
        
        resultText.append(directive + "\n")
        lastEmittedLine = line
    }
    
    /// Compiles and executes Swift `code` with access to bindings.
    func executeCode(_ code: String, atLine line: Int) throws {
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
        
        try executeSwiftCodeDynamically(code, bindings: bindings, context: self)
    }
    
    /// Returns the result of evaluating Swift `expression`.
    func evaluateExpression(_ expression: String, atLine line: Int) throws -> Any {
        emitLineDirective(line)
        return try evaluateSwiftExpression(expression, bindings: bindings)
    }
}

// MARK: - Child Executor

/// Allows block code to execute children via __children__[0].execute(__context__).
class ChildExecutor {
    let children: [ASTNode]
    let context: ExecutionContext
    
    init(children: [ASTNode], context: ExecutionContext) {
        self.children = children
        self.context = context
    }
    
    subscript(index: Int) -> ChildExecutor {
        ChildExecutor(children: [children[index]], context: context)
    }
    
    func execute(_ context: ExecutionContext) throws {
        try children.forEach { try $0.execute(context) }
    }
}

// MARK: - Dynamic Swift Execution

/// Compiles and executes Swift `code` by creating a temporary file, compiling with swiftc, and running it.
private func executeSwiftCodeDynamically(
    _ code: String,
    bindings: [String: Any],
    context: ExecutionContext
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
        context.resultText.append(output)
    }
}

/// Returns the result of evaluating Swift `expression`.
private func evaluateSwiftExpression(
    _ expression: String,
    bindings: [String: Any]
) throws -> Any {
    // Create code that prints the expression result
    let code = "print(\(expression), terminator: \"\")"
    
    let tempContext = ExecutionContext(bindings: bindings)
    try executeSwiftCodeDynamically(code, bindings: bindings, context: tempContext)
    
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

// MARK: - Template Execution

/// Returns the generated text from executing `ast` with `bindings`.
func executeTemplate(
    _ ast: BlockNode,
    filename: String = "stdin",
    lineDirective: String = "//# sourceLocation(file: \"%(file)s\", line: %(line)d)",
    bindings: [String: Any] = [:]
) throws -> String {
    let context = ExecutionContext(
        filename: filename,
        lineDirective: lineDirective,
        bindings: bindings
    )
    
    try ast.execute(context)
    
    return context.resultText.joined()
}

