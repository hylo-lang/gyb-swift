# Development Notes

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

### See Also

`.cursorrules` prompt file.

### Testing

The test suite translates doctests from the original gyb.py:

```bash
swift test
```

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
