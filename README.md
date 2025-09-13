# MacDBG

[![macOS](https://img.shields.io/badge/macOS-12.0+-blue.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.5+-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/License-GPL-green.svg)](LICENSE)

A modern native macOS debugger built with SwiftUI and LLDB, inspired by x64dbg. The latest version includes a high-performance C++ disassembly core and a Python-based LLDB bridge for responsive, real-time debugging on macOS.

## Features

- 🔍 **Process Debugging** - Attach to and debug running processes
- 📱 **Native SwiftUI Interface** - Modern macOS design with familiar debugging layout
- ⚡ **Real-time Disassembly** - View and edit assembly instructions live
- 🧠 **Memory Inspector** - Hex editor with ASCII representation
- 📊 **Register Viewer** - Monitor CPU register states
- 🎯 **Jump Visualization** - Visual control flow arrows like x64dbg
- 🔧 **Instruction Assembly** - Assemble x64 instructions to machine code
- 💻 **CLI Interface** - Command-line debugging capabilities
- 🛡️ **Security Aware** - Respects macOS security boundaries

<!-- Screenshots can be added under docs/ when available -->

## Quick Start

### Prerequisites

- macOS 12.0 or later
- Xcode with Swift 5.5+
- Python 3 with LLDB module (included with Xcode)

### Building

```bash
# Clone this repository and enter the project directory
# git clone <repo-url>
# cd MacDBG

# Option 1: Build the SwiftUI .app bundle via the helper script
chmod +x build.sh
./build.sh

# Option 2: Build CLI with Swift Package Manager
swift build
```

### Running

```bash
# GUI Application (after using build.sh)
open MacDBG.app

# Command Line Interface (SwiftPM executable target)
swift run macdbg-cli
```

## Basic Usage

1. **Launch MacDBG**
2. **Select a process** from the sidebar
3. **Click "Attach"** to begin debugging
4. **Use F7/F8/F9** for step into/over/continue
5. **View disassembly** in the main panel
6. **Monitor registers** and memory in side panels

## Project Structure

```
MacDBG/
├── src/                           # Core Swift application source
│   ├── MacDBGApp.swift                   # SwiftUI app entry point
│   ├── ContentView.swift                 # Primary UI layout (MacDBG V3)
│   ├── DataModels.swift                  # Core data models
│   ├── DebugControlsView.swift           # Debug action buttons
│   ├── DebugEngine.swift                 # Scripted/legacy LLDB driving utilities
│   ├── DebuggerController.swift          # Main debugging controller and state
│   ├── DebuggerViews.swift               # Aggregated/legacy view helpers
│   ├── DisassemblyView.swift             # Assembly viewer
│   ├── InstructionAssembler.swift        # x64 instruction assembler
│   ├── JumpTracker.swift                 # Jump instruction analysis
│   ├── JumpVisualizationView.swift       # Visual control-flow arrows
│   ├── LLDBManager.swift                 # Bridge to Python LLDB server
│   ├── LogView.swift                     # Debug logging interface
│   ├── LoggingSystem.swift               # Logging utilities
│   ├── MemoryView.swift                  # Hex/ASCII memory viewer
│   ├── ProcessListView.swift             # Process selection interface
│   ├── RegistersView.swift               # CPU register display
│   ├── TestTarget.c                      # Small test target (example)
│   ├── AIAssistantView.swift             # AI assistant interface
│   ├── AIChatView.swift                  # AI chat functionality
│   ├── AIModelManager.swift              # AI model management
│   ├── DebugLogger.swift                 # Debug logging utilities
│   ├── StringsView.swift                 # String analysis view
│   └── XRefsView.swift                   # Cross-reference analysis
├── cli/                          # Command-line interface target (SwiftPM)
│   └── main.swift               # CLI implementation and commands
├── cpp/                          # High-performance disassembly engine
│   ├── DisassemblyEngine.cpp    # C++ engine implementation
│   ├── DisassemblyEngine.hpp    # C++ engine public API
│   ├── MacDBGBridge.hpp         # C/ObjC bridge header for Swift interop
│   ├── MacDBGBridge.mm          # Objective-C++ bridge implementation
│   ├── AIModelBridge.hpp        # AI model bridge header
│   ├── AIModelBridge.mm         # AI model bridge implementation
│   ├── AIModelManager.cpp       # AI model manager implementation
│   └── AIModelManager.hpp       # AI model manager header
├── ai-backend/                   # AI backend integration
│   ├── include/ai-backend/       # AI backend headers
│   │   ├── llmodel.h            # LLM model interface
│   │   └── llmodel_c.h          # C interface for LLM
│   └── src/                      # AI backend source
│       └── llmodel_c.cpp        # C implementation for LLM
├── Resources/                    # Supporting resources
│   ├── lldb_server.py           # Python LLDB bridge/server
│   └── lldb_server_original.py  # Original LLDB server (backup)
├── models/                       # AI model files
│   ├── README.md                # Model documentation
│   └── qwen2.5-coder-3b-instruct-q4_0.gguf  # AI model file
├── test_program.dSYM/            # Debug symbols for test program
│   └── Contents/                 # Debug symbol contents
│       ├── Info.plist           # Debug symbol info
│       └── Resources/            # Debug symbol resources
│           └── DWARF/            # DWARF debug information
│               └── test_program  # Test program debug info
├── MacDBG-Bridging-Header.h     # Objective-C bridging header
├── MacDBG.entitlements          # macOS app entitlements
├── Package.swift                 # Swift Package Manager configuration
├── build.sh                      # Builds a standalone MacDBG.app bundle
├── debug_logger.py              # Python debug logging utility
├── download_model.sh            # AI model download script
├── libAIBridge.dylib            # AI bridge dynamic library
├── listfiles.sh                 # Helper script for listing files
├── plan.txt                     # Project planning document
├── properlayout.txt             # Layout documentation
└── README.md                    # This file
```


**Instruction Assembler (subset mapping example):**
```swift
class InstructionAssembler {
    // x64 instruction to opcode mapping (subset shown)
    private static let instructionMap: [String: String] = [
        // Conditional jumps (1-byte relative jumps)
        "je": "74",     "jz": "74",     // Jump if Equal/Zero
        "jne": "75",    "jnz": "75",    // Jump if Not Equal/Not Zero
        "ja": "77",     "jnbe": "77",   // Jump if Above/Not Below or Equal
        "jae": "73",    "jnb": "73",    "jnc": "73",    // Jump if Above or Equal
        "jb": "72",     "jnae": "72",   "jc": "72",     // Jump if Below/Carry
        "jbe": "76",    "jna": "76",    // Jump if Below or Equal
        "jg": "7f",     "jnle": "7f",   // Jump if Greater
        "jge": "7d",    "jnl": "7d",    // Jump if Greater or Equal
        "jl": "7c",     "jnge": "7c",   // Jump if Less
        "jle": "7e",    "jng": "7e",    // Jump if Less or Equal
        "jo": "70",     "jno": "71",    // Jump if Overflow/No Overflow
        "js": "78",     "jns": "79",    // Jump if Sign/No Sign
        "jp": "7a",     "jpe": "7a",    // Jump if Parity/Parity Even
        "jnp": "7b",    "jpo": "7b",    // Jump if No Parity/Parity Odd
        
        // Control flow
        "nop": "90",    // No Operation
        "ret": "c3",    "retf": "cb",   // Return Near/Far
        "int3": "cc",   "int": "cd",    // Interrupt 3/General Interrupt
        "hlt": "f4",    // Halt
        "jmp": "eb",    "call": "e8",   // Jump/Call (short/near)
        
        // Flag operations
        "clc": "f8",    "stc": "f9",    // Clear/Set Carry Flag
        "cli": "fa",    "sti": "fb",    // Clear/Set Interrupt Flag
        "cld": "fc",    "std": "fd",    // Clear/Set Direction Flag
        "cmc": "f5",    // Complement Carry Flag
        "sahf": "9e",   "lahf": "9f",   // Store/Load AH into Flags
        "pushf": "9c",  "popf": "9d",   // Push/Pop Flags
        
        // Data conversion
        "cbw": "66 98", "cwde": "98",   "cdq": "99",
        "xlat": "d7",   // Table Look-up Translation
        "daa": "27",    "das": "2f",    // Decimal Adjust AL
        "aaa": "37",    "aas": "3f",    // ASCII Adjust AL
        
        // Register operations (all GPRs supported)
        "push rax": "50", "push eax": "50", "push ax": "66 50",
        "push rcx": "51", "push ecx": "51", "push cx": "66 51",
        "push rdx": "52", "push edx": "52", "push dx": "66 52",
        "push rbx": "53", "push ebx": "53", "push bx": "66 53",
        "push rsp": "54", "push esp": "54", "push sp": "66 54",
        "push rbp": "55", "push ebp": "55", "push bp": "66 55",
        "push rsi": "56", "push esi": "56", "push si": "66 56",
        "push rdi": "57", "push edi": "57", "push di": "66 57",
        
        "pop rax": "58", "pop eax": "58", "pop ax": "66 58",
        "pop rcx": "59", "pop ecx": "59", "pop cx": "66 59",
        "pop rdx": "5a", "pop edx": "5a", "pop dx": "66 5a",
        "pop rbx": "5b", "pop ebx": "5b", "pop bx": "66 5b",
        "pop rsp": "5c", "pop esp": "5c", "pop sp": "66 5c",
        "pop rbp": "5d", "pop ebp": "5d", "pop bp": "66 5d",
        "pop rsi": "5e", "pop esi": "5e", "pop si": "66 5e",
        "pop rdi": "5f", "pop edi": "5f", "pop di": "66 5f",
        
        // Increment/Decrement operations
        "inc rax": "48 ff c0", "inc eax": "ff c0", "inc ax": "66 ff c0",
        "inc rcx": "48 ff c1", "inc ecx": "ff c1", "inc cx": "66 ff c1",
        "inc rdx": "48 ff c2", "inc edx": "ff c2", "inc dx": "66 ff c2",
        "inc rbx": "48 ff c3", "inc ebx": "ff c3", "inc bx": "66 ff c3",
        "inc rsp": "48 ff c4", "inc esp": "ff c4", "inc sp": "66 ff c4",
        "inc rbp": "48 ff c5", "inc ebp": "ff c5", "inc bp": "66 ff c5",
        "inc rsi": "48 ff c6", "inc esi": "ff c6", "inc si": "66 ff c6",
        "inc rdi": "48 ff c7", "inc edi": "ff c7", "inc di": "66 ff c7",
        
        "dec rax": "48 ff c8", "dec eax": "ff c8", "dec ax": "66 ff c8",
        "dec rcx": "48 ff c9", "dec ecx": "ff c9", "dec cx": "66 ff c9",
        "dec rdx": "48 ff ca", "dec edx": "ff ca", "dec dx": "66 ff ca",
        "dec rbx": "48 ff cb", "dec ebx": "ff cb", "dec bx": "66 ff cb",
        "dec rsp": "48 ff cc", "dec esp": "ff cc", "dec sp": "66 ff cc",
        "dec rbp": "48 ff cd", "dec ebp": "ff cd", "dec bp": "66 ff cd",
        "dec rsi": "48 ff ce", "dec esi": "ff ce", "dec si": "66 ff ce",
        "dec rdi": "48 ff cf", "dec edi": "ff cf", "dec di": "66 ff cf"
    ]
}
```

## Architecture

MacDBG uses a modern Swift architecture with these key components:

- **SwiftUI Frontend** - Native macOS interface with professional debugging layout (MacDBG V3 UI)
- **C++ Disassembly Core** - High-performance instruction storage, indexing, and jump analysis (`cpp/DisassemblyEngine.hpp`)
- **Objective-C++ Bridge** - Efficient interop between Swift and C++ (`cpp/MacDBGBridge.mm` / `.hpp`)
- **LLDB Python Bridge** - Structured JSON messages and event streaming via `Resources/lldb_server.py`
- **Real-time Event System** - Handles debugging events (breakpoints, steps, stops) and updates UI/CLI
- **Memory Safety** - Safe memory reading/writing with validation
- **Security Awareness** - Respects macOS security boundaries and SIP protection

## CLI Commands

```bash
ps                    # List running processes
attach <pid>          # Attach to process
detach                # Detach from the currently attached process
step, s              # Step single instruction  
continue, c          # Continue execution
dis, disassemble     # Show disassembly
reg, registers       # Show register values
mem <addr> [bytes]   # Read memory
log                  # Show debug log
status              # Show debugger status
quit, exit           # Exit the CLI (detaches first if attached)
```

## Key Features

### Jump Visualization
- Automatic detection of jump instructions
- Color-coded arrows (blue=conditional, green=unconditional, red=calls)
- Click to navigate to jump targets
- Off-screen target indicators

### Live Instruction Editing
- Type new assembly instructions directly in disassembly view
- Real-time validation and byte generation
- Safe editing (only when process is stopped)
- Support for 100+ x64 instructions

### Memory Operations
- Hex viewer with 16-byte rows
- ASCII representation
- Byte-level editing
- Pattern filling and export

### Security Features
- Automatic blocking of system processes
- SIP (System Integrity Protection) awareness
- Permission validation
- Safe defaults

## Stepping System

MacDBG features a robust and intelligent stepping system that handles complex debugging scenarios, including system library navigation and automatic instruction highlighting.

### Stepping Operations

- **Step Into (F7)** - Steps into function calls, following execution into subroutines
- **Step Over (F8)** - Steps over function calls, executing them without entering
- **Step Out (Shift+F7)** - Steps out of the current function to its caller
- **Step Until User Code** - Automatically steps until reaching user code (exits system libraries)

### Intelligent System Library Handling

The stepping system includes sophisticated logic for handling system library code:

- **Automatic Detection** - Identifies when execution is in system libraries (e.g., `libsystem_kernel.dylib`)
- **Aggressive Recovery** - When stuck on system instructions (like `retq`), automatically attempts multiple recovery strategies:
  - Multiple `StepOut` attempts to exit system functions
  - Brief `Continue`/`Stop` cycles to force execution progression
  - Fallback to alternative PC detection methods
- **Smart PC Detection** - Uses multiple methods to determine the current program counter:
  - Direct frame access
  - Register inspection (RIP register)
  - LLDB command execution
  - Fallback to previous PC if all else fails

### Real-time UI Updates

The stepping system ensures the UI stays synchronized with execution:

- **Automatic Disassembly Refresh** - Disassembly view automatically updates to show the current instruction
- **Instruction Highlighting** - Current instruction is highlighted in the disassembly view
- **Auto-scroll** - View automatically scrolls to the current instruction location
- **Register Updates** - CPU registers are refreshed after each step
- **Event-driven Architecture** - Uses structured JSON events between Python LLDB server and Swift UI

### Event System Architecture

```
User Action (Step Into)
    ↓
Swift UI (DebuggerController)
    ↓
LLDB Manager (JSON Command)
    ↓
Python LLDB Server (Resources/lldb_server.py)
    ↓
LLDB API (Step Execution)
    ↓
Event Thread (Process State Detection)
    ↓
Structured Event (JSON Response)
    ↓
Swift UI (Update Disassembly + Highlight)
```

### Stepping Event Types

- `step_into` - Step into function calls
- `step_over` - Step over function calls  
- `step_out` - Step out of current function
- `step_until_user_code` - Step until reaching user code

### Error Recovery

The system includes comprehensive error recovery:

- **Invalid Frame Handling** - Gracefully handles cases where LLDB frames become invalid
- **PC Change Detection** - Monitors for cases where the program counter doesn't advance
- **System Library Stuck Detection** - Identifies when execution is stuck in system code
- **Multiple Recovery Attempts** - Tries various strategies to unstick execution

### Performance Optimizations

- **Throttled Requests** - Prevents excessive disassembly requests
- **Cached Disassembly** - Maintains disassembly cache for better performance
- **Efficient Event Handling** - Uses structured JSON for fast communication
- **Background Processing** - Stepping operations don't block the UI

## Development

### Building from Source

```bash
# Install Command Line Tools and ensure Python LLDB is available (via Xcode)
xcode-select --install

# Build GUI bundle
chmod +x build.sh && ./build.sh && open MacDBG.app

# Build & run CLI
swift build
swift run macdbg-cli
```

### Architecture Overview

MacDBG follows a pragmatic MVVM architecture with a native high-performance core:

1. **Views** - SwiftUI components for the user interface (`src/*View.swift`)
2. **ViewModels/Controllers** - Business logic and state (`DebuggerController`, `DebugEngine`)
3. **Models** - Data structures and process state (`DataModels.swift`)
4. **Services/Bridge** - LLDB Python server and Swift <-> C++ interop (`LLDBManager.swift`, `cpp/*`, `Resources/lldb_server.py`)

## Status

### ✅ Completed
- Process attachment and debugging
- Real-time disassembly with jump visualization
- **Intelligent stepping system** with system library handling
- **Automatic instruction highlighting** and UI synchronization
- Memory and register inspection
- Live instruction editing
- CLI interface
- Security framework

### 🔄 In Progress
- Enhanced breakpoint management
- Call stack navigation
- Symbol resolution
- Plugin system

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Testing

You can use your own local binaries or small toy programs to attach and test stepping/disassembly. Ensure the process is not SIP-protected or otherwise restricted.

## Requirements

- **macOS**: 12.0 (Monterey) or later
- **Xcode**: 13.0+ with Swift 5.5+ and LLDB
- **Python**: 3.7+ with `lldb` module (provided with Xcode)
- **Hardware**: Intel or Apple Silicon Mac

## License

This project is licensed under the GPL License - see the [LICENSE](LICENSE) file for details.

Some components reference x64dbg (GPL) and use LLDB (LLVM License). See individual files for specific licensing information.

## Acknowledgments

- Inspired by [x64dbg](https://x64dbg.com) - Windows debugger
- Built with Apple's [LLDB](https://lldb.llvm.org) framework
- UI design patterns from professional debugging tools

---

**MacDBG** - Professional macOS debugging with modern Swift architecture and a high-performance C++ core.
