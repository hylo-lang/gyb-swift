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

```swift
- Hello -
%{
let x = 42
func succ(_ a: Int) -> Int { a + 1 }
}%
I can assure you that ${x} < ${succ(x)}
% if y > 7 {
%   for i in 0..<3 {
y is greater than seven!
%   }
% }
- The End. -
```

## Usage

```bash
# Process a template file
gyb-swift input.gyb -o output.swift

# With variable bindings
gyb-swift -Dx=42 -Dname=value input.gyb -o output.swift

# Read from stdin, write to stdout
echo "Hello ${x}!" | gyb-swift -Dx=World -

# Run self-tests
gyb-swift --test
```

## Implementation Notes

### Translation Approach

This implementation translates gyb.py's functionality while adapting for Swift's characteristics:

1. **SwiftSyntax Integration**: Uses SwiftSyntax/SwiftParser for tokenizing embedded Swift code
2. **Documentation**: All functions documented using the contract-based approach from [Better Code Chapter 2](https://github.com/stlab/better-code/blob/main/better-code/src/chapter-2-contracts.md)
3. **Type Safety**: Leverages Swift's type system where Python used dynamic typing
4. **Error Handling**: Uses Swift's error handling instead of Python exceptions

### Key Differences from Python gyb.py

#### Dynamic Execution Model

The most significant difference is in code execution:

- **Python gyb.py**: Uses `eval()` and `exec()` for runtime code evaluation with a shared execution context
- **gyb-swift**: Compiles and executes Swift code dynamically using `swiftc`

This means that in the current implementation:
- Each code block is compiled separately
- Variable persistence across template sections has limitations
- Performance is slower due to compilation overhead

#### Limitations

1. **Variable Scope**: Variables defined in `%{...}%` blocks may not persist to `${...}` substitutions due to separate compilation units
2. **Performance**: Dynamic compilation is slower than Python's eval()
3. **Control Flow**: Complex control structures spanning multiple template sections may not work as expected
4. **State**: No shared mutable state across executions like Python's global scope

### Production Considerations

For a production-ready gyb-swift, consider:

1. **Swift REPL Integration**: Integrate with Swift's REPL for true interactive execution
2. **Compilation Strategy**: Collect all template code and compile as single unit
3. **Caching**: Cache compiled code for better performance
4. **Sandbox**: Ensure proper sandboxing of executed code

## Architecture

The implementation consists of:

- **StringUtilities.swift**: String manipulation and line tracking
- **Tokenization.swift**: Template tokenization and Swift code parsing
- **AST.swift**: Abstract syntax tree nodes and parsing
- **ExecutionContext.swift**: Runtime execution environment
- **gyb_swift.swift**: Command-line interface

## Testing

The test suite translates doctests from the original gyb.py:

```bash
swift test
```

Tests cover:
- String utilities
- Tokenization
- Template parsing
- Execution (with limitations noted above)

## Building

```bash
swift build
```

## License

This translation maintains compatibility with the Swift project's license. See the original gyb.py for licensing details.

## Acknowledgments

- Original gyb.py by the Swift team
- Better Code documentation methodology by Sean Parent and Dave Abrahams
- SwiftSyntax library by Apple

## Future Improvements

- [ ] Integrate Swift REPL for proper eval() equivalent
- [ ] Single compilation unit execution model
- [ ] Performance optimizations (compilation caching)
- [ ] Extended control flow support
- [ ] Debug mode with verbose output
- [ ] Template include/import system

