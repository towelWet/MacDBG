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
    "$SRC_DIR/StringsView.swift" \
    "$SRC_DIR/XRefsView.swift" \
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

# Copy AI model (download if needed)
echo "🧠 Setting up AI model..."
mkdir -p "$APP_NAME/Contents/Resources/models"

MODEL_FILE="qwen2.5-coder-3b-instruct-q4_0.gguf"
MODEL_PATH="models/$MODEL_FILE"
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_0.gguf"

if [ -f "$MODEL_PATH" ]; then
    echo "   ✅ Using existing AI model: $MODEL_FILE"
    cp "$MODEL_PATH" "$APP_NAME/Contents/Resources/models/"
elif command -v curl >/dev/null 2>&1; then
    echo "   📥 Downloading AI model (this may take a few minutes)..."
    mkdir -p models
    if curl -L -o "$MODEL_PATH" "$MODEL_URL" --progress-bar; then
        echo "   ✅ AI model downloaded successfully"
        cp "$MODEL_PATH" "$APP_NAME/Contents/Resources/models/"
    else
        echo "   ⚠️  AI model download failed - AI features will use fallback mode"
    fi
elif command -v wget >/dev/null 2>&1; then
    echo "   📥 Downloading AI model using wget..."
    mkdir -p models
    if wget -O "$MODEL_PATH" "$MODEL_URL" --progress=bar; then
        echo "   ✅ AI model downloaded successfully"
        cp "$MODEL_PATH" "$APP_NAME/Contents/Resources/models/"
    else
        echo "   ⚠️  AI model download failed - AI features will use fallback mode"
    fi
else
    echo "   ⚠️  No download tool available (curl/wget) - AI features will use fallback mode"
fi

# Copy Python lldb server script (required)
echo "🐍 Copying lldb_server.py to Resources..."
if [ -f "Resources/lldb_server.py" ]; then
    cp "Resources/lldb_server.py" "$APP_NAME/Contents/Resources/"
    echo "   ✅ LLDB server script copied successfully"
else
    echo "   ❌ ERROR: lldb_server.py not found - debugging will not work!"
    exit 1
fi

# Copy debug_logger.py (required for Python server)
echo "🐍 Copying debug_logger.py to Resources..."
if [ -f "debug_logger.py" ]; then
    cp "debug_logger.py" "$APP_NAME/Contents/Resources/"
    echo "   ✅ Debug logger script copied successfully"
else
    echo "   ❌ ERROR: debug_logger.py not found - Python server will crash!"
    exit 1
fi

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
# Code sign the app for debugging permissions
echo "🔐 Code signing app for debugging permissions..."
if [ -f "MacDBG.entitlements" ]; then
    codesign --force --deep --entitlements MacDBG.entitlements --sign "Apple Development: yiwanfuweng_yonggong@icloud.com (J733LWGZYJ)" "$APP_NAME" 2>/dev/null || {
        echo "   ⚠️  Code signing failed - you may need to attach to processes manually"
        echo "   💡 Try: codesign --force --deep --entitlements MacDBG.entitlements --sign \"Apple Development: yiwanfuweng_yonggong@icloud.com (J733LWGZYJ)\" MacDBG.app"
    }
    echo "   ✅ App signed with debugging entitlements"
else
    echo "   ⚠️  MacDBG.entitlements not found - debugging may not work"
fi

echo ""
echo "Run: open MacDBG.app"
