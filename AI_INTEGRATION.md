# MacDBG AI Integration

## Overview

MacDBG now includes AI-powered analysis capabilities using the Qwen2.5-Coder-3B-Instruct model. This integration provides intelligent code analysis, debugging suggestions, and automated insights to enhance the reverse engineering and debugging experience.

## Features

### 🤖 AI Assistant Tab
- **Dedicated AI Interface**: Switch between "Main" and "AI Assistant" tabs
- **Real-time Analysis**: Analyze disassembly, registers, and memory patterns
- **Suggestion Management**: View, organize, and manage AI-generated insights
- **Custom Prompts**: Ask specific questions about your code

### 🔍 Context-Aware Analysis
- **Instruction Analysis**: Right-click any instruction for detailed AI commentary
- **Function Analysis**: Analyze entire function blocks for patterns and vulnerabilities
- **Register State Explanation**: Understand what register values reveal about execution
- **Memory Pattern Recognition**: Identify data structures and interesting values
- **Breakpoint Suggestions**: Get AI recommendations for optimal debugging points

### ⚙️ AI Configuration
- **Temperature Control**: Adjust response creativity (0.0 - 2.0)
- **Top-P Sampling**: Control response diversity (0.0 - 1.0)
- **Token Limits**: Set maximum response length (64 - 2048 tokens)
- **Model Management**: Load/unload AI models as needed

## Architecture

### C++ Bridge (`cpp/`)
- **AIModelManager.hpp/cpp**: Core AI model management and inference
- **AIModelBridge.hpp/mm**: Objective-C++ bridge for Swift integration

### Swift Integration (`src/`)
- **AIModelManager.swift**: Swift wrapper for AI functionality
- **AIAssistantView.swift**: Complete AI assistant user interface
- **DisassemblyView.swift**: Enhanced with AI context menus

### Model Support
- **Format**: GGUF (GGML Universal Format)
- **Model**: Qwen2.5-Coder-3B-Instruct (1.9GB)
- **Quantization**: Q4_0 (4-bit quantization for efficiency)
- **Context**: 2048 tokens

## Usage

### 1. Basic AI Analysis
1. Launch MacDBG
2. Switch to "AI Assistant" tab
3. Select analysis type (Disassembly, Registers, Memory, Custom)
4. Click "Analyze" button

### 2. Context Menu Analysis
1. Right-click on any disassembly instruction
2. Select "🤖 AI Analysis" menu
3. Choose specific analysis type:
   - Analyze Instruction
   - Analyze Function
   - Suggest Breakpoints
   - Explain Register State
   - Analyze Memory Pattern

### 3. Custom AI Prompts
1. Switch to "AI Assistant" tab
2. Select "Custom" analysis type
3. Enter your specific question or prompt
4. Click "Analyze"

## AI Suggestion Types

| Type | Icon | Description |
|------|------|-------------|
| Code Analysis | 🔍 | Assembly code structure and flow analysis |
| Comment | 💬 | Detailed instruction explanations |
| Breakpoint Suggestion | 🔴 | Optimal debugging breakpoint locations |
| Register Analysis | 🖥️ | CPU register state interpretation |
| Memory Analysis | 🧠 | Memory pattern and data structure analysis |
| Vulnerability | ⚠️ | Security issue identification |
| Optimization | ⚡ | Performance improvement suggestions |

## Technical Implementation

### Model Loading
```swift
// Automatic model loading on app startup
let aiManager = AIModelManager()
await aiManager.loadModel()
```

### Async Analysis
```swift
// Non-blocking AI analysis
let suggestion = await aiManager.analyzeDisassembly(
    disassembly,
    context: "Current PC: 0x\(String(format: "%llx", programCounter))"
)
```

### Context Menu Integration
```swift
// Right-click AI analysis
.contextMenu {
    Menu("🤖 AI Analysis") {
        Button("Analyze Instruction") { analyzeInstruction() }
        Button("Analyze Function") { analyzeFunction() }
        // ... more options
    }
}
```

## Configuration

### AI Settings
Access via the gear icon in the AI Assistant tab:

- **Temperature**: Controls randomness (0.0 = focused, 2.0 = creative)
- **Top-P**: Controls diversity (0.0 = conservative, 1.0 = diverse)
- **Max Tokens**: Response length limit (64-2048 tokens)

### Model Management
- **Auto-load**: Model loads automatically on app startup
- **Manual Control**: Load/unload models as needed
- **Status Indicator**: Green/red dot shows model status

## Performance Considerations

### Memory Usage
- **Model Size**: ~1.9GB RAM for loaded model
- **Context Window**: 2048 tokens maximum
- **Caching**: Intelligent suggestion caching

### Response Times
- **Mock Mode**: Instant responses (current implementation)
- **Real Inference**: 1-5 seconds depending on prompt complexity
- **Async Processing**: Non-blocking UI updates

## Future Enhancements

### Planned Features
- **Real llama.cpp Integration**: Replace mock implementation
- **Model Switching**: Support multiple AI models
- **Custom Model Loading**: Load user-provided GGUF models
- **Batch Analysis**: Analyze multiple code sections simultaneously
- **Export AI Insights**: Save analysis results to files

### Advanced Capabilities
- **Pattern Recognition**: Learn from user debugging sessions
- **Automated Patching**: AI-suggested code modifications
- **Vulnerability Detection**: Enhanced security analysis
- **Code Reconstruction**: High-level language reconstruction

## Troubleshooting

### Common Issues
1. **Model Not Loading**: Check file path and permissions
2. **Slow Responses**: Reduce max tokens or temperature
3. **Memory Issues**: Ensure sufficient RAM (8GB+ recommended)
4. **Build Errors**: Verify C++ compiler and Swift toolchain

### Debug Information
- Check Debug Log for AI-related messages
- Verify model file exists in `models/` directory
- Ensure C++ bridge compiled successfully

## Development Notes

### Mock Implementation
The current implementation uses mock responses for demonstration. To enable real AI inference:

1. Integrate llama.cpp library
2. Replace mock functions in `AIModelManager.cpp`
3. Link against llama.cpp binaries
4. Test with actual model inference

### Code Structure
```
cpp/
├── AIModelManager.hpp      # C++ AI manager interface
├── AIModelManager.cpp      # C++ AI manager implementation
├── AIModelBridge.hpp       # Objective-C++ bridge header
└── AIModelBridge.mm        # Objective-C++ bridge implementation

src/
├── AIModelManager.swift    # Swift AI manager wrapper
└── AIAssistantView.swift   # AI assistant UI
```

## License

This AI integration follows the same license as the main MacDBG project. The Qwen2.5-Coder model is subject to its own licensing terms.

---

**Note**: This is a comprehensive AI integration framework. The current implementation provides mock responses for demonstration purposes. Real AI inference requires integration with the llama.cpp library and proper model loading.
