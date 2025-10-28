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

  @Option(
    name: .customShort("D"), parsing: .upToNextOption,
    help: """
      Variable bindings in the form NAME=VALUE. Can be specified multiple times.
      Example: -Dx=42 -Dname=value
      """)
  var defines: [String] = []

  @Option(
    help: """
      Line directive format string with \\(file) and \\(line) placeholders to emit in output.
      Example: '//# line \\(line) "\\(file)"'
      Default: no line directives in output
      """)
  var lineDirective: String = ""

  @Flag(
    help: """
      Emit #sourceLocation directives in template output and fix their placement.
      Sets lineDirective to '#sourceLocation(file: "\\(file)", line: \\(line))' and applies
      automatic fixing to ensure directives are in valid positions.
      """)
  var templateGeneratesSwift: Bool = false

  @Flag(
    help: """
      Force compilation of template instead of using Swift interpreter.
      By default, templates are executed via Swift interpreter on non-Windows platforms for speed.
      This flag forces compilation, useful for testing the compilation path.
      """)
  var forceTemplateCompilation: Bool = false

  @Flag(help: "Dump the parsed template AST to stdout")
  var dump: Bool = false

  @Flag(help: "Dump the generated Swift code to stdout (without executing)")
  var dumpCode: Bool = false

  /// Reads the template, parses it, executes it with bindings, and writes output.
  mutating func run() throws {

    // Set lineDirective if --template-generates-swift is specified
    var effectiveLineDirective = lineDirective
    if templateGeneratesSwift {
      effectiveLineDirective = #"#sourceLocation(file: "\(file)", line: \(line))"#
    }

    // Parse variable bindings
    let bindings: [String: String] = try Dictionary(
      uniqueKeysWithValues: defines.map { define in
        let parts = define.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else {
          throw ValidationError("Invalid binding format: \(define). Expected NAME=VALUE")
        }
        return (String(parts[0]), String(parts[1]))
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
      let source = URL(fileURLWithPath: file)
      templateText = try String(contentsOf: source, encoding: .utf8)
      filename = file
    }

    // Parse template
    let ast = try parseTemplate(filename: filename, text: templateText)

    // Dump AST if requested
    if dump {
      print(ast)
      return
    }

    // Create code generator for template
    let generator = CodeGenerator(
      templateText: templateText,
      filename: filename,
      lineDirective: effectiveLineDirective,
      emitLineDirectives: !effectiveLineDirective.isEmpty
    )

    // Dump generated Swift code if requested
    if dumpCode {
      let code = generator.generateCompleteProgram(ast, bindings: bindings)
      print(code)
      return
    }

    // Change to template's directory for relative imports
    if file != "-" {
      let templateDir = URL(fileURLWithPath: file).deletingLastPathComponent()
      _ = FileManager.default.changeCurrentDirectoryPath(templateDir.path)
    }

    // Execute template
    var result = try generator.execute(
      ast, bindings: bindings, forceCompilation: forceTemplateCompilation)

    // Fix #sourceLocation directives in template output if needed
    if templateGeneratesSwift {
      result = fixSourceLocationPlacement(result)
    }

    // Write output
    if output == "-" {
      print(result, terminator: "")
    } else {
      let destination = URL(fileURLWithPath: output)
      try result.write(to: destination, atomically: true, encoding: .utf8)
    }
  }
}
