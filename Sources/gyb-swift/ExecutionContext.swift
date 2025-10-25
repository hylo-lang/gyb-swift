import Algorithms
import Foundation

// MARK: - Errors

/// Errors that can occur during template execution.
enum GYBError: Error, CustomStringConvertible {
    /// Generated Swift code failed to compile, with compiler output.
    case compilationFailed(String)
    /// Compiled program failed during execution, with error output.
    case executionFailed(String)
    /// Template parsing failed, with error description.
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

/// Generates Swift code from AST nodes with consistent configuration.
struct CodeGenerator {
    /// Original template text for source location tracking.
    let templateText: String
    /// Template filename for source location directives.
    let filename: String
    /// Line directive format with `\(file)` and `\(line)` placeholders.
    let lineDirective: String
    /// Whether to emit source location directives in generated code.
    let emitSourceLocation: Bool

    /// Precomputed line start positions for efficient line number calculation.
    private let lineStarts: [String.Index]

    init(
        templateText: String,
        filename: String = "",
        lineDirective: String = #"#sourceLocation(file: "\(file)", line: \(line))"#,
        emitSourceLocation: Bool = true
    ) {
        self.templateText = templateText
        self.filename = filename
        self.lineDirective = lineDirective
        self.emitSourceLocation = emitSourceLocation
        self.lineStarts = getLineStarts(templateText)
    }

    /// Returns Swift code executing `nodes`, batching consecutive output nodes into print statements.
    func generateCode(for nodes: [ASTNode]) -> String {
        // Group consecutive output nodes together; keep code nodes separate
        let chunks = nodes.chunked { prev, curr in
            isOutputNode(prev) && isOutputNode(curr)
        }

        let lines = chunks.map { chunk -> String in
            // Code nodes are emitted directly
            if let code = chunk.first as? CodeNode {
                return String(code.code)
            }

            // Output nodes are batched into print statements
            return printStatement(for: chunk)
        }

        return lines.joined(separator: "\n")
    }

    /// Returns a complete Swift program for `ast` with `bindings`.
    func generateCompleteProgram(_ ast: AST, bindings: [String: String] = [:]) -> String {
        // Generate bindings code
        let bindingsCode =
            bindings
            .filter { $0.key != "__children__" && $0.key != "__context__" }
            .map { "let \($0.key) = \(String(reflecting: $0.value))" }
            .joined(separator: "\n")

        // Generate template code
        let templateCode = generateCode(for: ast)

        return """
            import Foundation

            // Bindings
            \(bindingsCode)

            // Generated code
            \(templateCode)

            """
    }

    /// Executes `ast` with `bindings` by compiling and running generated Swift code.
    func execute(_ ast: AST, bindings: [String: String] = [:]) throws -> String {
        // Generate complete Swift program without source location directives
        let executionGenerator = CodeGenerator(
            templateText: templateText,
            filename: filename,
            lineDirective: lineDirective,
            emitSourceLocation: false
        )
        let swiftCode = executionGenerator.generateCompleteProgram(ast, bindings: bindings)

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
            let errorMessage =
                String(data: errorData, encoding: .utf8) ?? "Unknown compilation error"
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
            let errorMessage =
                String(data: errorData, encoding: .utf8) ?? "Unknown execution error"
            throw GYBError.executionFailed(errorMessage)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    /// Returns the start position of `nodes`'s first element.
    private func sourceLocationIndex(for nodes: AST.SubSequence) -> String.Index {
        let first = nodes.first!

        if let literal = first as? LiteralNode {
            return literal.text.startIndex
        } else if let substitution = first as? SubstitutionNode {
            return substitution.expression.startIndex
        }
        fatalError("Unexpected node type: \(type(of: first))")
    }

    /// Returns `nodes`'s text content as strings, with substitutions formatted as `\(expression)`.
    private func textContent(from nodes: AST.SubSequence) -> [String] {
        return nodes.map { node in
            if let literal = node as? LiteralNode {
                return String(literal.text)
            } else if let substitution = node as? SubstitutionNode {
                return #"\(\#(substitution.expression))"#
            }
            fatalError("Unexpected node type: \(type(of: node))")
        }
    }

    /// Returns a Swift print statement outputting `nodes`'s combined text, prefixed by a source location directive when configured.
    private func printStatement(for nodes: AST.SubSequence) -> String {
        let combined = textContent(from: nodes).joined()
        var result: [String] = []

        // Emit source location directive if requested
        if emitSourceLocation {
            let index = sourceLocationIndex(for: nodes)
            let lineNumber = getLineNumber(for: index, in: templateText, lineStarts: lineStarts)
            let directive = formatSourceLocation(
                lineDirective, filename: filename, line: lineNumber)
            result.append(directive)
        }

        let escaped = escapeForSwiftMultilineString(combined)
        result.append("print(\"\"\"\n\(escaped)\n\"\"\", terminator: \"\")")

        return result.joined(separator: "\n")
    }

    /// Returns whether `node` represents template output.
    private func isOutputNode(_ node: ASTNode) -> Bool {
        return node is LiteralNode || node is SubstitutionNode
    }
}

/// Returns `text` escaped for Swift multiline string literals, preserving `\(...)` interpolations.
private func escapeForSwiftMultilineString(_ text: String) -> String {
    return
        text
        .replacingOccurrences(of: #"\"#, with: #"\\"#)
        .replacingOccurrences(of: #"""""#, with: #"\"\"\""#)
        .replacingOccurrences(of: #"\\("#, with: #"\("#)
}

/// Returns `template`'s `\(file)` and `\(line)` placeholders replaced by `filename` and `line`.
private func formatSourceLocation(_ template: String, filename: String, line: Int) -> String {
    return
        template
        .replacingOccurrences(of: #"\(file)"#, with: filename)
        .replacingOccurrences(of: #"\(line)"#, with: "\(line)")
}
