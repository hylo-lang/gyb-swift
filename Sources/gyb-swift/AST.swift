import Foundation

// MARK: - AST Node Protocol

/// A node in the template abstract syntax tree.
protocol ASTNode: CustomStringConvertible {}

// MARK: - Literal Node

/// Literal text from the template.
struct LiteralNode: ASTNode {
    let text: Substring
    let line: Int
    
    var description: String {
        "Literal: \(text.prefix(20))\(text.dropFirst(20).isEmpty ? "" : "...")"
    }
}

// MARK: - Code Node

/// Swift code to be executed, which may produce output via print().
struct CodeNode: ASTNode {
    let code: Substring
    let line: Int
    
    var description: String {
        "Code: {\(code.prefix(30))\(code.dropFirst(30).isEmpty ? "" : "...")}"
    }
}

// MARK: - Substitution Node

/// A ${...} expression whose result is converted to text and inserted into the output.
struct SubstitutionNode: ASTNode {
    let expression: Substring
    let line: Int
    
    var description: String {
        "Substitution: ${\(expression)}"
    }
}

// MARK: - Block Node

/// A sequence of child nodes, possibly with code controlling their execution (e.g., loop or conditional).
struct BlockNode: ASTNode {
    let code: Substring?
    let children: [ASTNode]
    let line: Int
    
    init(code: Substring? = nil, children: [ASTNode], line: Int = 1) {
        self.code = code
        self.children = children
        self.line = line
    }
    
    var description: String {
        let parts = [
            "Block: [",
            code.map { "\n  Code: {\($0.prefix(40))\($0.dropFirst(40).isEmpty ? "" : "...")}" } ?? "",
            "\n  [\n",
            children.map { "    \($0.description.replacingOccurrences(of: "\n", with: "\n    "))\n" }.joined(),
            "  ]\n]"
        ]
        return parts.joined()
    }
}

// MARK: - Helper Functions

/// Extracts code content from a gybBlockOpen token (%{...}%).
/// Removes the %{ prefix, }% suffix, and optional trailing newline.
private func extractCodeFromBlockToken(_ token: Substring) -> Substring {
    let suffixLength = token.last?.isNewline == true ? 3 : 2  // }%\n or }%
    return token.dropFirst(2).dropLast(suffixLength)
}

// MARK: - Parse Context

/// Maintains parsing state while converting templates to AST.
struct ParseContext {
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
    mutating func advance(to index: String.Index) {
        assert(index >= position)
        position = index
    }
    
    /// Returns AST nodes parsed from the template.
    mutating func parseNodes() throws -> [ASTNode] {
        var nodes: [ASTNode] = []
        var tokenIterator = TemplateTokens(text: templateText)
        
        while let token = tokenIterator.next() {
            advance(to: token.text.startIndex)
            let line = currentLine
            
            switch token.kind {
            case .literal:
                if !token.text.isEmpty {
                    nodes.append(LiteralNode(text: token.text, line: line))
                }
                
            case .substitutionOpen:
                // Extract expression between ${ and }
                nodes.append(SubstitutionNode(expression: token.text.dropFirst(2).dropLast(), line: line))
                
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
                            blockChildren.append(SubstitutionNode(expression: nextToken.text.dropFirst(2).dropLast(), line: childLine))
                        case .gybLines:
                            // Check if this nested line also has unmatched braces
                            let childCode = extractCodeFromLines(nextToken.text)
                            let childOpenBraces = childCode.filter { $0 == "{" }.count
                            let childCloseBraces = childCode.filter { $0 == "}" }.count
                            
                            if childOpenBraces > childCloseBraces {
                                // Nested block - recursively collect its children
                                var nestedChildren: [ASTNode] = []
                                while let nestedToken = tokenIterator.next() {
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
                                        nestedChildren.append(SubstitutionNode(expression: nestedToken.text.dropFirst(2).dropLast(), line: currentLine))
                                    case .symbol:
                                        nestedChildren.append(LiteralNode(text: nestedToken.text.prefix(1), line: currentLine))
                                    default:
                                        break
                                    }
                                }
                                blockChildren.append(BlockNode(code: childCode, children: nestedChildren, line: childLine))
                            } else {
                                blockChildren.append(CodeNode(code: childCode, line: childLine))
                            }
                        case .gybBlockOpen:
                            blockChildren.append(CodeNode(code: extractCodeFromBlockToken(nextToken.text), line: childLine))
                        case .symbol:
                            blockChildren.append(LiteralNode(text: nextToken.text.prefix(1), line: childLine))
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
                nodes.append(CodeNode(code: extractCodeFromBlockToken(token.text), line: line))
                
            case .gybBlockClose:
                // }% - should not appear in isolation
                break
                
            case .symbol:
                // %% or $$ becomes single % or $
                nodes.append(LiteralNode(text: token.text.prefix(1), line: line))
            }
        }
        
        return nodes
    }
    
    /// Returns executable code from %-lines with leading % and indentation removed.
    private func extractCodeFromLines(_ text: Substring) -> Substring {
        text.split(omittingEmptySubsequences: false) { $0.isNewline }
            .map { line in
                line.drop { $0 != "%" }.dropFirst().drop(while: \.isWhitespace)
            }
            .joined(separator: "\n")[...]
    }
}

/// Returns an AST from template `text`.
func parseTemplate(filename: String, text: String) throws -> BlockNode {
    var context = ParseContext(filename: filename, text: text)
    let nodes = try context.parseNodes()
    return BlockNode(children: nodes, line: 1)
}

