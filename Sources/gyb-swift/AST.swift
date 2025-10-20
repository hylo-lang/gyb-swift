import Foundation

// MARK: - AST Node Protocol

/// A node in the template abstract syntax tree.
protocol ASTNode: CustomStringConvertible {
    /// Executes the node, appending its output to `context.resultText`.
    func execute(_ context: ExecutionContext) throws
}

// MARK: - Literal Node

/// Fixed text that appears directly in the output.
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

/// Swift code to be executed, which may produce output via print().
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

/// A ${...} expression whose result is converted to text and inserted into the output.
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

/// A sequence of child nodes, possibly with code controlling their execution (e.g., loop or conditional).
struct BlockNode: ASTNode {
    let code: String?
    let children: [ASTNode]
    let line: Int
    
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
            try children.forEach { try $0.execute(context) }
        }
    }
    
    var description: String {
        var result = "Block: ["
        if let code = code {
            result += "\n  Code: {\(code.prefix(40))\(code.count > 40 ? "..." : "")}"
        }
        result += "\n  [\n"
        result += children
            .map { "    \($0.description.replacingOccurrences(of: "\n", with: "\n    "))\n" }
            .joined()
        result += "  ]\n]"
        return result
    }
}

// MARK: - Parse Context

/// Maintains parsing state while converting templates to AST.
class ParseContext {
    let filename: String
    let templateText: String
    private(set) var position: String.Index
    private let lineStarts: [String.Index]
    
    init(filename: String, text: String) {
        self.filename = filename
        self.templateText = text
        self.position = text.startIndex
        self.lineStarts = getLineStarts(text)
    }
    
    /// Returns the current line number.
    var currentLine: Int {
        lineStarts.firstIndex { $0 > position }.map { $0 } ?? lineStarts.count
    }
    
    /// Advances position to `index`.
    ///
    /// - Precondition: `index >= position`.
    func advance(to index: String.Index) {
        assert(index >= position)
        position = index
    }
    
    /// Returns AST nodes parsed from the template.
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
    
    /// Returns executable code from %-lines with leading % and indentation removed.
    private func extractCodeFromLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var trimmed = String(line)
                // Remove leading whitespace and %
                if let percentIndex = trimmed.firstIndex(of: "%") {
                    trimmed = String(trimmed[trimmed.index(after: percentIndex)...])
                }
                // Remove leading space if present
                if trimmed.first == " " {
                    trimmed = String(trimmed.dropFirst())
                }
                return trimmed
            }
            .joined(separator: "\n")
    }
}

/// Returns an AST from template `text`.
func parseTemplate(filename: String, text: String) throws -> BlockNode {
    let context = ParseContext(filename: filename, text: text)
    let nodes = try context.parseNodes()
    return BlockNode(children: nodes, line: 1)
}

