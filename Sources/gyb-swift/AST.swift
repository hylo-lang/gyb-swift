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
        let parts = [
            "Block: [",
            code.map { "\n  Code: {\($0.prefix(40))\($0.count > 40 ? "..." : "")}" } ?? "",
            "\n  [\n",
            children.map { "    \($0.description.replacingOccurrences(of: "\n", with: "\n    "))\n" }.joined(),
            "  ]\n]"
        ]
        return parts.joined()
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
        var tokenIterator = TemplateTokens(text: templateText)
        
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
                
                // Check if this line has an unmatched opening brace
                let openBraces = code.filter { $0 == "{" }.count
                let closeBraces = code.filter { $0 == "}" }.count
                
                if openBraces > closeBraces {
                    // This line opens a block - collect children until % }
                    var blockChildren: [ASTNode] = []
                    
                    while let nextToken = tokenIterator.next() {
                        advance(to: nextToken.startIndex)
                        let childLine = currentLine
                        
                        if nextToken.kind == .gybLinesClose {
                            // Found closing % }
                            break
                        }
                        
                        // Parse child token
                        switch nextToken.kind {
                        case .literal:
                            if !nextToken.text.isEmpty {
                                blockChildren.append(LiteralNode(text: nextToken.text, line: childLine))
                            }
                        case .substitutionOpen:
                            let expr = String(nextToken.text.dropFirst(2).dropLast())
                            blockChildren.append(SubstitutionNode(expression: expr, line: childLine))
                        case .gybLines:
                            // Check if this nested line also has unmatched braces
                            let childCode = extractCodeFromLines(nextToken.text)
                            let childOpenBraces = childCode.filter { $0 == "{" }.count
                            let childCloseBraces = childCode.filter { $0 == "}" }.count
                            
                            if childOpenBraces > childCloseBraces {
                                // Nested block - recursively collect its children
                                var nestedChildren: [ASTNode] = []
                                while let nestedToken = tokenIterator.next() {
                                    advance(to: nestedToken.startIndex)
                                    if nestedToken.kind == .gybLinesClose {
                                        break
                                    }
                                    // Simple parsing of nested children (could be made recursive)
                                    switch nestedToken.kind {
                                    case .literal:
                                        if !nestedToken.text.isEmpty {
                                            nestedChildren.append(LiteralNode(text: nestedToken.text, line: currentLine))
                                        }
                                    case .substitutionOpen:
                                        let expr = String(nestedToken.text.dropFirst(2).dropLast())
                                        nestedChildren.append(SubstitutionNode(expression: expr, line: currentLine))
                                    case .symbol:
                                        nestedChildren.append(LiteralNode(text: String(nestedToken.text.first!), line: currentLine))
                                    default:
                                        break
                                    }
                                }
                                blockChildren.append(BlockNode(code: childCode, children: nestedChildren, line: childLine))
                            } else {
                                blockChildren.append(CodeNode(code: childCode, line: childLine))
                            }
                        case .gybBlockOpen:
                            let blockCode = String(nextToken.text.dropFirst(2).dropLast(2))
                            blockChildren.append(CodeNode(code: blockCode, line: childLine))
                        case .symbol:
                            let char = String(nextToken.text.first!)
                            blockChildren.append(LiteralNode(text: char, line: childLine))
                        default:
                            break
                        }
                    }
                    
                    // Create block with control code and children
                    nodes.append(BlockNode(code: code, children: blockChildren, line: line))
                } else {
                    // Regular code line without block structure
                    nodes.append(CodeNode(code: code, line: line))
                }
                
            case .gybLinesClose:
                // End marker - should be handled by block parsing above
                // If we see it here, it's unmatched
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
        text.split(omittingEmptySubsequences: false) { $0.isNewline }
            .map { line in
                line.drop { $0 != "%" }.dropFirst().drop(while: \.isWhitespace)
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

