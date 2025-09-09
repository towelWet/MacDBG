#!/bin/bash
set -e

echo "🚀 Building MacDBG - ULTRA FAST Performance Debugger"
echo "==================================================="

# Define directories
SRC_DIR="src"
APP_NAME="MacDBG.app"
EXECUTABLE_NAME="MacDBG"

# Clean previous build
echo "🧹 Cleaning previous build artifacts..."
rm -rf "$APP_NAME"

# Compile C++ AI bridge with real llama.cpp integration via llama-cli
echo "🔧 Compiling C++ AI bridge with llama-cli integration..."
clang++ -std=c++17 -fPIC -shared \
    -framework Foundation -framework AppKit \
    -fobjc-arc \
    -Wno-deprecated-declarations \
    cpp/AIModelManager.cpp \
    cpp/AIModelBridge.mm \
    -o libAIBridge.dylib

# Compile with MAXIMUM optimization for speed using original layout
echo "⚙️ Compiling ULTRA optimized Swift sources with AI integration..."
swiftc -O -whole-module-optimization \
    -framework Foundation -framework SwiftUI -framework AppKit \
    -I cpp \
    -L . \
    -lAIBridge \
    -import-objc-header MacDBG-Bridging-Header.h \
    "$SRC_DIR/MacDBGApp.swift" \
    "$SRC_DIR/ContentView.swift" \
    "$SRC_DIR/DebuggerController.swift" \
    "$SRC_DIR/DisassemblyView.swift" \
    "$SRC_DIR/JumpTracker.swift" \
    "$SRC_DIR/JumpVisualizationView.swift" \
    "$SRC_DIR/DebugControlsView.swift" \
    "$SRC_DIR/ProcessListView.swift" \
    "$SRC_DIR/LoggingSystem.swift" \
    "$SRC_DIR/RegistersView.swift" \
    "$SRC_DIR/MemoryView.swift" \
    "$SRC_DIR/LogView.swift" \
    "$SRC_DIR/LLDBManager.swift" \
    "$SRC_DIR/DataModels.swift" \
    "$SRC_DIR/InstructionAssembler.swift" \
           "$SRC_DIR/AIModelManager.swift" \
           "$SRC_DIR/AIAssistantView.swift" \
           "$SRC_DIR/AIChatView.swift" \
           "$SRC_DIR/AIChatView_Enhanced.swift" \
    -o "$EXECUTABLE_NAME"

echo "✅ Compilation successful."

# Create the .app bundle structure
echo "📦 Creating application bundle: $APP_NAME..."
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

# Copy the executable
mv "$EXECUTABLE_NAME" "$APP_NAME/Contents/MacOS/"

# Copy the AI bridge library
echo "🤖 Copying AI bridge library..."
cp "libAIBridge.dylib" "$APP_NAME/Contents/MacOS/"

# Fix library path in the executable
echo "🔧 Fixing library paths..."
install_name_tool -change "libAIBridge.dylib" "@executable_path/libAIBridge.dylib" "$APP_NAME/Contents/MacOS/MacDBG"

# Copy AI model
echo "🧠 Copying AI model..."
mkdir -p "$APP_NAME/Contents/Resources/models"
cp "models/qwen2.5-coder-3b-instruct-q4_0.gguf" "$APP_NAME/Contents/Resources/models/"

# Copy Python lldb server script
echo "🐍 Copying lldb_server.py to Resources..."
cp "Resources/lldb_server.py" "$APP_NAME/Contents/Resources/"

# Create the Info.plist
echo "📝 Creating Info.plist..."
cat > "$APP_NAME/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourcompany.macdbg</string>
    <key>CFBundleName</key>
    <string>MacDBG</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMainNibFile</key>
    <string>MainMenu</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🎉 ULTRA FAST build complete!"
echo ""
echo "🔥 Performance optimizations applied:"
echo "   ✅ Maximum Swift optimization (-O -whole-module-optimization)"
echo "   ✅ Original layout preserved (correct UI structure)"
echo "   ✅ Limited rendering to 500 instructions max"
echo "   ✅ Reduced logging overhead"
echo "   ✅ Optimized compilation"
echo ""
echo "🚀 Expected performance improvements:"
echo "   ⚡ Faster compilation and startup"
echo "   ⚡ Reduced memory usage"
echo "   ⚡ Better UI responsiveness"
echo "   ⚡ Same familiar interface"
echo ""
echo "Run: open MacDBG.app"
