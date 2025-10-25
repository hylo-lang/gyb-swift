import Foundation

// MARK: - AST Node Protocol

/// A node in the template abstract syntax tree.
protocol ASTNode: CustomStringConvertible {}

// MARK: - Literal Node

/// Literal text from the template.
struct LiteralNode: ASTNode {
    let text: Substring
    
    var description: String {
        "Literal: \(text.prefix(20))\(text.dropFirst(20).isEmpty ? "" : "...")"
    }
}

// MARK: - Code Node

/// Swift code to be executed (from %-lines or %{...}% blocks).
struct CodeNode: ASTNode {
    let code: Substring
    
    var description: String {
        "Code: {\(code.prefix(30))\(code.dropFirst(30).isEmpty ? "" : "...")}"
    }
}

// MARK: - Substitution Node

/// A ${...} expression whose result is converted to text and inserted into the output.
struct SubstitutionNode: ASTNode {
    let expression: Substring
    
    var description: String {
        "Substitution: ${\(expression)}"
    }
}

// MARK: - Block Node (Top-Level Container Only)

/// Top-level container for template nodes.
/// Note: This is just a container; nesting is handled by Swift's compiler, not by the parser.
struct BlockNode: ASTNode {
    let children: [ASTNode]
    
    init(children: [ASTNode]) {
        self.children = children
    }
    
    var description: String {
        "Block: [\n" + children.map { "  \($0.description)\n" }.joined() + "]"
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
    
    init(filename: String, text: String) {
        self.filename = filename
        self.templateText = text
    }
    
    /// Returns AST nodes parsed from the template.
    /// Simply converts each token to a node - no nesting logic.
    mutating func parseNodes() throws -> [ASTNode] {
        return TemplateTokens(text: templateText).compactMap { token in
            switch token.kind {
            case .literal:
                return token.text.isEmpty ? nil : LiteralNode(text: token.text)
                
            case .substitutionOpen:
                // Extract expression between ${ and }
                return SubstitutionNode(expression: token.text.dropFirst(2).dropLast())
                
            case .gybLines:
                // Extract code from %-lines
                return CodeNode(code: extractCodeFromLines(token.text))
                
            case .gybBlockOpen:
                // Extract code between %{ and }%
                return CodeNode(code: extractCodeFromBlockToken(token.text))
                
            case .gybBlockClose:
                // }% - should not appear in isolation (tokenizer handles it)
                return nil
                
            case .symbol:
                // %% or $$ becomes single % or $
                return LiteralNode(text: token.text.prefix(1))
            }
        }
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
    return BlockNode(children: nodes)
}
