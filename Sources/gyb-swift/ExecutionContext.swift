import Foundation

// MARK: - Execution Context

/// Runtime context for executing template code.
///
/// Maintains variable bindings, accumulated output text, and line directives
/// for error reporting.
class ExecutionContext {
    /// The accumulated output text.
    var resultText: [String] = []
    
    /// Variable bindings available to template code.
    var bindings: [String: Any]
    
    /// Format string for line directives.
    ///
    /// Expects %(file)s and %(line)d placeholders.
    let lineDirective: String
    
    /// The current template filename.
    let filename: String
    
    /// Current line number in output.
    private var lastEmittedLine: Int = 0
    
    /// Child nodes available to block code via __children__.
    private var children: [ASTNode]?
    
    /// Creates an execution context.
    ///
    /// - Parameters:
    ///   - filename: Template filename for diagnostics.
    ///   - lineDirective: Format for line directives.
    ///   - bindings: Initial variable bindings.
    init(
        filename: String = "stdin",
        lineDirective: String = "//# sourceLocation(file: \"%(file)s\", line: %(line)d)",
        bindings: [String: Any] = [:]
    ) {
        self.filename = filename
        self.lineDirective = lineDirective
        self.bindings = bindings
    }
    
    /// Creates a child context for executing a block's children.
    ///
    /// - Parameter children: The child nodes.
    /// - Returns: New context sharing bindings but with __children__ available.
    func createChildContext(children: [ASTNode]) -> ExecutionContext {
        let child = ExecutionContext(
            filename: filename,
            lineDirective: lineDirective,
            bindings: bindings
        )
        child.children = children
        return child
    }
    
    /// Emits a line directive if needed.
    ///
    /// - Parameter line: The source line number.
    private func emitLineDirective(_ line: Int) {
        guard !lineDirective.isEmpty && line != lastEmittedLine else { return }
        
        let directive = lineDirective
            .replacingOccurrences(of: "%(file)s", with: filename)
            .replacingOccurrences(of: "%(line)d", with: "\(line)")
        
        resultText.append(directive + "\n")
        lastEmittedLine = line
    }
    
    /// Executes Swift code.
    ///
    /// Compiles and runs the code with access to all bindings.
    ///
    /// - Parameters:
    ///   - code: Swift code to execute.
    ///   - line: Source line number for diagnostics.
    /// - Throws: If code execution fails.
    /// - Complexity: Depends on code complexity; compilation is O(n) in code length.
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
    
    /// Evaluates a Swift expression.
    ///
    /// - Parameters:
    ///   - expression: Swift expression to evaluate.
    ///   - line: Source line number for diagnostics.
    /// - Returns: The result of evaluating the expression.
    /// - Throws: If evaluation fails.
    func evaluateExpression(_ expression: String, atLine line: Int) throws -> Any {
        emitLineDirective(line)
        return try evaluateSwiftExpression(expression, bindings: bindings)
    }
}

// MARK: - Child Executor

/// Helper for executing child nodes from block code.
///
/// Allows block code to call __children__[0].execute(__context__).
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

/// Executes Swift code dynamically by compiling and running it.
///
/// This is a simplified implementation. A production version would:
/// - Create a temporary Swift source file
/// - Include all bindings as variables
/// - Compile using swiftc
/// - Execute the resulting binary
/// - Capture output and return values
///
/// - Parameters:
///   - code: Swift code to execute.
///   - bindings: Available variables.
///   - context: Execution context for output.
/// - Throws: If compilation or execution fails.
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

/// Evaluates a Swift expression dynamically.
///
/// - Parameters:
///   - expression: Swift expression to evaluate.
///   - bindings: Available variables.
/// - Returns: The evaluated result.
/// - Throws: If evaluation fails.
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

/// Formats a value as Swift source code.
///
/// - Parameter value: The value to format.
/// - Returns: Swift source representation.
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

/// Executes a parsed template AST.
///
/// Runs the template with the given bindings and returns the generated text.
///
/// - Parameters:
///   - ast: The parsed template AST.
///   - filename: Template filename for diagnostics.
///   - lineDirective: Format for line directives.
///   - bindings: Variable bindings for template code.
/// - Returns: The generated output text.
/// - Throws: If execution fails.
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

