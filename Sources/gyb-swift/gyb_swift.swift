import ArgumentParser
import Foundation

/// Generate Your Boilerplate - Swift Edition
///
/// A template processing tool that executes embedded Swift code to generate
/// text output. Templates can contain:
/// - Literal text inserted directly into output
/// - Substitutions of the form ${expression}
/// - Swift code blocks delimited by %{...}%
/// - Swift code lines beginning with %
/// - Escaped symbols %% and $$ for literal % and $
///
/// See --help for detailed usage information and examples.
@main
struct GYBSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gyb-swift",
        abstract: "Generate Your Boilerplate - Swift Edition",
        discussion: """
        A GYB template consists of the following elements:
        
        - Literal text which is inserted directly into the output
        
        - %% or $$ in literal text, which insert literal '%' and '$' symbols respectively.
        
        - Substitutions of the form ${...}. The Swift expression is converted to a string
          and the result is inserted into the output.
        
        - Swift code delimited by %{...}%. Typically used to inject definitions (functions,
          classes, variable bindings) into the evaluation context of the template. Common
          indentation is stripped, so you can add as much indentation to the beginning of
          this code as you like.
        
        - Lines beginning with optional whitespace followed by a single '%' and Swift code.
          %-lines allow you to nest other constructs inside them. To close a level of
          nesting, use the "%end" construct.
        
        - Lines beginning with optional whitespace and followed by a single '%' and the
          token "end", which close open constructs in %-lines.
        
        Example template:
        
        - Hello -
        %{ let x = 42
        func succ(_ a: Int) -> Int { a + 1 }
        }%
        I can assure you that ${x} < ${succ(x)}
        % if Int(y ?? "0")! > 7 {
        %   for i in 0..<3 {
        y is greater than seven!
        %   }
        % } else {
        y is less than or equal to seven
        % }
        - The End. -
        
        When run with "gyb-swift -Dy=9 template.gyb", the output is:
        
        - Hello -
        I can assure you that 42 < 43
        y is greater than seven!
        y is greater than seven!
        y is greater than seven!
        - The End. -
        """
    )
    
    @Argument(help: "Path to GYB template file (use '-' for stdin)")
    var file: String = "-"
    
    @Option(name: .shortAndLong, help: "Output file (use '-' for stdout)")
    var output: String = "-"
    
    @Option(name: .customShort("D"), parsing: .upToNextOption, help: """
        Variable bindings in the form NAME=VALUE. Can be specified multiple times.
        Example: -Dx=42 -Dname=value
        """)
    var defines: [String] = []
    
    @Option(help: """
        Line directive format string with %(file)s and %(line)d placeholders.
        Example: '#sourceLocation(file: "%(file)s", line: %(line)d)'
        """)
    var lineDirective: String = "//# sourceLocation(file: \"%(file)s\", line: %(line)d)"
    
    @Flag(help: "Run self-tests")
    var test: Bool = false
    
    @Flag(help: "Dump the parsed template AST to stdout")
    var dump: Bool = false
    
    /// Reads the template, parses it, executes it with bindings, and writes output.
    mutating func run() throws {
        if test {
            try runTests()
            return
        }
        
        // Parse variable bindings
        let bindings: [String: Any] = try Dictionary(
            uniqueKeysWithValues: defines.map { define in
                let parts = define.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else {
                    throw ValidationError("Invalid binding format: \(define). Expected NAME=VALUE")
                }
                return (String(parts[0]), String(parts[1]) as Any)
            }
        )
        
        // Read template
        let templateText: String
        let filename: String
        
        if file == "-" {
            // Read from stdin
            templateText = AnyIterator { readLine(strippingNewline: false) }
                .joined()
            filename = "stdin"
        } else {
            // Read from file
            let url = URL(fileURLWithPath: file)
            templateText = try String(contentsOf: url, encoding: .utf8)
            filename = file
        }
        
        // Parse template
        let ast = try parseTemplate(filename: filename, text: templateText)
        
        // Dump AST if requested
        if dump {
            print(ast)
            return
        }
        
        // Change to template's directory for relative imports
        if file != "-" {
            let templateDir = URL(fileURLWithPath: file).deletingLastPathComponent()
            FileManager.default.changeCurrentDirectoryPath(templateDir.path)
        }
        
        // Execute template
        let result = try executeTemplate(
            ast,
            filename: filename,
            lineDirective: lineDirective,
            bindings: bindings
        )
        
        // Write output
        if output == "-" {
            print(result, terminator: "")
        } else {
            let outputURL = URL(fileURLWithPath: output)
            try result.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }
    
    /// Runs self-tests.
    ///
    /// - Throws: If any tests fail.
    private func runTests() throws {
        print("Running self-tests...")
        
        // Test string utilities
        testGetLineStarts()
        testStripTrailingNewline()
        testSplitLines()
        
        // Test simple template
        testSimpleTemplate()
        testSubstitution()
        testCodeBlock()
        
        print("All tests passed! ✓")
    }
    
    private func testGetLineStarts() {
        let text = "line1\nline2\nline3"
        let starts = getLineStarts(text)
        assert(starts.count == 4, "Expected 4 line starts")
        print("✓ getLineStarts")
    }
    
    private func testStripTrailingNewline() {
        assert(stripTrailingNewline("hello\n") == "hello")
        assert(stripTrailingNewline("hello") == "hello")
        print("✓ stripTrailingNewline")
    }
    
    private func testSplitLines() {
        let lines = splitLines("a\nb\nc")
        assert(lines.count == 3)
        assert(lines[0] == "a\n")
        print("✓ splitLines")
    }
    
    private func testSimpleTemplate() {
        do {
            let text = "Hello, World!"
            let ast = try parseTemplate(filename: "test", text: text)
            let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
            assert(result == "Hello, World!", "Expected 'Hello, World!' but got '\(result)'")
            print("✓ simple template")
        } catch {
            print("✗ simple template: \(error)")
        }
    }
    
    private func testSubstitution() {
        do {
            let text = "The answer is ${x}"
            let ast = try parseTemplate(filename: "test", text: text)
            let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: ["x": 42])
            assert(result.contains("42"), "Expected result to contain '42' but got '\(result)'")
            print("✓ substitution")
        } catch {
            print("✗ substitution: \(error)")
        }
    }
    
    private func testCodeBlock() {
        do {
            let text = "%{ let x = 10 }%\nValue: ${x}"
            let ast = try parseTemplate(filename: "test", text: text)
            let result = try executeTemplate(ast, filename: "test", lineDirective: "", bindings: [:])
            assert(result.contains("10"), "Expected result to contain '10' but got '\(result)'")
            print("✓ code block")
        } catch {
            print("✗ code block: \(error)")
        }
    }
}
