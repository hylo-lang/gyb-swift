# GYB-Swift: Generate Your Boilerplate in Swift

This is a Swift translation of the Python `gyb.py` tool from the Swift compiler project. GYB is a template processor that executes embedded code to generate text output.

## Overview

GYB-Swift translates the functionality of Python's gyb.py to Swift, with embedded Swift code replacing embedded Python code. The tool uses SwiftSyntax for tokenizing Swift code and provides a familiar template syntax.

## Template Syntax

A GYB template consists of:

- **Literal text**: Inserted directly into output
- **`%%` or `$$`**: Escaped symbols for literal `%` and `$`
- **`${expression}`**: Substitutions - the Swift expression result is inserted
- **`%{...}%`**: Code blocks for definitions (functions, variables, etc.)
- **`% code`**: Code lines beginning with `%`
- **`%end`**: Closes code line blocks

## Example

**Template (`example.gyb`):**
```swift
- Hello -
%{
let x = 42
func succ(_ a: Int) -> Int { a + 1 }
}%
I can assure you that ${x} < ${succ(x)}
% let y = 10
% if y > 7 {
%   for i in 0..<3 {
y is greater than seven!
%   }
% }
- The End. -
```

**Command:**
```bash
gyb-swift example.gyb
```

**Output:**
```
- Hello -
I can assure you that 42 < 43
y is greater than seven!
y is greater than seven!
y is greater than seven!
- The End. -
```

## Usage

```bash
# Process a template file
gyb-swift input.gyb -o output.swift

# With variable bindings
gyb-swift input.gyb -D x=42 -D name=value -o output.swift

# Read from stdin, write to stdout
echo "Hello ${x}!" | gyb-swift - -D x=World

# Dump the parsed AST
gyb-swift --dump input.gyb

# Dump generated Swift code without executing
gyb-swift --dump-code input.gyb

# Custom source location directives
gyb-swift --line-directive '#sourceLocation(file: "%(file)s", line: %(line)d)' input.gyb
```

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/gyb-swift.git
cd gyb-swift

# Build the project
swift build

# Run directly
swift run gyb-swift <template.gyb>

# Or install to use system-wide
swift build -c release
cp .build/release/gyb-swift /usr/local/bin/
```

## Features

- ✅ Full Swift language support in templates
- ✅ Control flow (`for`, `if`, `while`, `switch`)
- ✅ SwiftSyntax integration for accurate code parsing
- ✅ `#sourceLocation` directives for error mapping
- ✅ Multiline string literals with interpolations in generated code
- ✅ `--dump-code` to inspect generated Swift
- ✅ Efficient `Substring` usage throughout
- ✅ Comprehensive test suite (44 tests)

---

## Development

### Translation Approach

This implementation translates gyb.py's functionality while adapting for Swift's characteristics:

1. **SwiftSyntax Integration**: Uses SwiftSyntax/SwiftParser for tokenizing embedded Swift code
2. **Documentation**: All functions documented using the contract-based approach from [Better Code Chapter 2](https://github.com/stlab/better-code/blob/main/better-code/src/chapter-2-contracts.md)
3. **Type Safety**: Leverages Swift's type system where Python used dynamic typing
4. **Error Handling**: Uses Swift's error handling instead of Python exceptions

### Execution Model

- **Python gyb.py**: Uses `eval()` and `exec()` for runtime code evaluation
- **gyb-swift**: Converts entire template to a single Swift program, compiles with `swiftc`, and executes

**Advantages:**
- Full Swift language support including control flow (`for`, `if`, `while`, etc.)
- Variables persist across template sections
- Type-safe Swift code execution

**Trade-offs:**
- Compilation overhead (slower than Python's eval)
- Requires `swiftc` to be available

### Source Location Mapping

gyb-swift emits `#sourceLocation` directives in generated code to map compiler errors back to template files:
- Template text and `${...}` expressions map to original template line numbers
- Syntax errors in templates show the correct file and line
- Makes debugging templates significantly easier

### String Handling Optimizations

gyb-swift uses `Substring` extensively to minimize memory allocations:
- Template tokens store `Substring` references (share original string storage)
- AST nodes use `Substring` for literals, code, and expressions
- Only convert to `String` at execution boundaries
- Efficient for large templates with minimal copying

### Architecture

The implementation consists of:

- **StringUtilities.swift**: String manipulation and line tracking
- **Tokenization.swift**: Template tokenization and Swift code parsing
- **AST.swift**: Abstract syntax tree nodes and parsing
- **ExecutionContext.swift**: Runtime execution environment
- **gyb_swift.swift**: Command-line interface

### Testing

The test suite translates doctests from the original gyb.py:

```bash
swift test
```

Tests cover:
- String utilities
- Tokenization
- Template parsing
- Code generation and execution

### Building from Source

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run tests
swift test
```

---

## License

This translation maintains compatibility with the Swift project's license. See the original gyb.py for licensing details.

## Acknowledgments

- Original gyb.py by the Swift team
- Better Code documentation methodology by Sean Parent and Dave Abrahams
- SwiftSyntax library by Apple

## Roadmap

- [ ] Compilation result caching for better performance
- [ ] Template include/import system
- [ ] Additional output formatters
- [ ] Watch mode for template development

