# MacDBG C++ Core Architecture

## Performance-Critical C++ Components

### 1. DisassemblyEngine (C++)
- **Fast instruction storage**: `std::vector<Instruction>` with O(1) access
- **Binary search**: For address lookups in O(log n)
- **Memory pools**: Preallocated instruction objects
- **SIMD-optimized**: Jump analysis using vectorized string operations

### 2. LLDBBridge (C++)  
- **Native LLDB API**: Direct C++ LLDB integration, no Python overhead
- **Background threads**: Async command processing
- **Circular buffers**: For register/memory updates
- **Zero-copy**: Memory mapping for large data

### 3. JumpAnalyzer (C++)
- **Compile-time lookup tables**: For instruction types
- **Trie-based parsing**: Fast operand parsing
- **Cached results**: Jump targets cached by address ranges
- **Parallel processing**: Multi-threaded jump analysis

### 4. Swift UI Bridge
- **Minimal data transfer**: Only visible rows sent to Swift
- **Differential updates**: Only changed instructions sent
- **Native Swift types**: Automatic bridging with `@objc`
- **Main thread scheduling**: C++ schedules UI updates

## Architecture Flow
```
LLDB ← C++ LLDBBridge ← C++ DisassemblyEngine ← Swift UI Bridge ← SwiftUI
```

## Performance Targets
- **Disassembly loading**: 10,000+ instructions < 10ms
- **Jump analysis**: 1,000 jumps < 1ms  
- **UI updates**: 60 FPS with 500+ visible rows
- **Step response**: < 50ms from command to UI update
