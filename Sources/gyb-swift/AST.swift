import Foundation

// MARK: - AST Node Protocol

/// A node in the template abstract syntax tree.
protocol ASTNode: CustomStringConvertible {
    /// Executes the node within the given context.
    ///
    /// - Parameter context: The execution environment containing bindings and output.
    /// - Postcondition: The node's output has been appended to context.resultText.
    func execute(_ context: ExecutionContext) throws
}

// MARK: - Literal Node

/// A literal text node.
///
/// Represents fixed text that appears directly in the output.
struct LiteralNode: ASTNode {
    let text: String
    let line: Int
    
    func execute(_ context: ExecutionContext) throws {
        context.resultText.append(text)
    }
    
    var description: String {
        "Literal: \(text.prefix(20))\(text.count > 20 ? "..." : "")"
    }
}

// MARK: - Code Node

/// An executable Swift code node.
///
/// Represents Swift code to be executed, which may produce output via print().
struct CodeNode: ASTNode {
    let code: String
    let line: Int
    
    func execute(_ context: ExecutionContext) throws {
        try context.executeCode(code, atLine: line)
    }
    
    var description: String {
        "Code: {\(code.prefix(30))\(code.count > 30 ? "..." : "")}"
    }
}

// MARK: - Substitution Node

/// A substitution expression node.
///
/// Represents a ${...} expression whose result is converted to text
/// and inserted into the output.
struct SubstitutionNode: ASTNode {
    let expression: String
    let line: Int
    
    func execute(_ context: ExecutionContext) throws {
        let result = try context.evaluateExpression(expression, atLine: line)
        context.resultText.append(String(describing: result))
    }
    
    var description: String {
        "Substitution: ${\(expression)}"
    }
}

// MARK: - Block Node

/// A block of child nodes.
///
/// Represents a sequence of AST nodes, possibly with associated code
/// that controls their execution (e.g., loop or conditional).
struct BlockNode: ASTNode {
    let code: String?
    let children: [ASTNode]
    let line: Int
    
    /// Creates a block with optional control code.
    ///
    /// If code is provided, it should reference __children__ to execute
    /// the child nodes.
    ///
    /// - Parameters:
    ///   - code: Optional Swift code controlling child execution.
    ///   - children: Child nodes in this block.
    ///   - line: Source line number for diagnostics.
    init(code: String? = nil, children: [ASTNode], line: Int = 1) {
        self.code = code
        self.children = children
        self.line = line
    }
    
    func execute(_ context: ExecutionContext) throws {
        if let code = code {
            // Execute code that may call children
            let childContext = context.createChildContext(children: children)
            try childContext.executeCode(code, atLine: line)
            context.resultText.append(contentsOf: childContext.resultText)
        } else {
            // Execute children directly
            for child in children {
                try child.execute(context)
            }
        }
    }
    
    var description: String {
        var result = "Block: ["
        if let code = code {
            result += "\n  Code: {\(code.prefix(40))\(code.count > 40 ? "..." : "")}"
        }
        result += "\n  [\n"
        for child in children {
            result += "    \(child.description.replacingOccurrences(of: "\n", with: "\n    "))\n"
        }
        result += "  ]\n]"
        return result
    }
}

// MARK: - Parse Context

/// Context for parsing templates into AST.
class ParseContext {
    let filename: String
    let templateText: String
    private(set) var position: String.Index
    private let lineStarts: [String.Index]
    
    /// Creates a parsing context.
    ///
    /// - Parameters:
    ///   - filename: Name of the template file for diagnostics.
    ///   - text: The template text to parse.
    init(filename: String, text: String) {
        self.filename = filename
        self.templateText = text
        self.position = text.startIndex
        self.lineStarts = getLineStarts(text)
    }
    
    /// Returns the current line number.
    ///
    /// - Complexity: O(log n) where n is the number of lines.
    var currentLine: Int {
        lineStarts.firstIndex { $0 > position }.map { $0 } ?? lineStarts.count
    }
    
    /// Advances position to the given index.
    ///
    /// - Precondition: index >= position.
    func advance(to index: String.Index) {
        assert(index >= position)
        position = index
    }
    
    /// Parses template tokens into AST nodes.
    ///
    /// - Returns: Array of parsed AST nodes.
    /// - Throws: If parsing fails due to malformed template.
    func parseNodes() throws -> [ASTNode] {
        var nodes: [ASTNode] = []
        let tokenIterator = TemplateTokenizer(text: templateText)
        
        while let token = tokenIterator.next() {
            let line = currentLine
            
            switch token.kind {
            case .literal:
                if !token.text.isEmpty {
                    nodes.append(LiteralNode(text: token.text, line: line))
                }
                
            case .substitutionOpen:
                // Extract expression between ${ and }
                let content = String(token.text.dropFirst(2).dropLast())
                nodes.append(SubstitutionNode(expression: content, line: line))
                
            case .gybLines:
                // Parse %-lines
                let code = extractCodeFromLines(token.text)
                nodes.append(CodeNode(code: code, line: line))
                
            case .gybLinesClose:
                // End marker - handled by block parsing
                break
                
            case .gybBlockOpen:
                // Extract code between %{ and }%
                let content = String(token.text.dropFirst(2).dropLast(2))
                nodes.append(CodeNode(code: content, line: line))
                
            case .gybBlockClose:
                // }% - should not appear in isolation
                break
                
            case .symbol:
                // %% or $$ becomes single % or $
                let char = String(token.text.first!)
                nodes.append(LiteralNode(text: char, line: line))
            }
        }
        
        return nodes
    }
    
    /// Extracts executable code from %-lines.
    ///
    /// Removes the leading % and common indentation from each line.
    private func extractCodeFromLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [String] = []
        
        for line in lines {
            var trimmed = String(line)
            // Remove leading whitespace and %
            if let percentIndex = trimmed.firstIndex(of: "%") {
                trimmed = String(trimmed[trimmed.index(after: percentIndex)...])
            }
            // Remove leading space if present
            if trimmed.first == " " {
                trimmed = String(trimmed.dropFirst())
            }
            result.append(trimmed)
        }
        
        return result.joined(separator: "\n")
    }
}

/// Parses a template into an AST.
///
/// Converts template text containing literal content, substitutions,
/// and embedded code into an executable abstract syntax tree.
///
/// - Parameters:
///   - filename: Name of template file for diagnostics.
///   - text: The template text.
/// - Returns: Root block node of the parsed template.
/// - Throws: If the template is malformed.
func parseTemplate(filename: String, text: String) throws -> BlockNode {
    let context = ParseContext(filename: filename, text: text)
    let nodes = try context.parseNodes()
    return BlockNode(children: nodes, line: 1)
}

