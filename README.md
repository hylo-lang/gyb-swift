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
gyb-swift --line-directive '#sourceLocation(file: "\(file)", line: \(line))' input.gyb
```

See `gyb-swift --help` for more information.

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
