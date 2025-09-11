#!/bin/bash

# MacDBG AI Model Download Script
MODEL_FILE="qwen2.5-coder-3b-instruct-q4_0.gguf"
MODEL_DIR="models"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_PATH" ] && [ $(stat -f%z "$MODEL_PATH") -gt 1000000 ]; then
    echo "✅ Real model already exists ($(du -h "$MODEL_PATH" | cut -f1))"
    exit 0
fi

echo "📥 Downloading AI model (2.1GB)..."
echo "🌐 Trying Hugging Face..."

if curl -L -o "$MODEL_PATH" "https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_0.gguf" --progress-bar --connect-timeout 30; then
    if [ $(stat -f%z "$MODEL_PATH") -gt 1000000 ]; then
        echo "✅ Download successful!"
        echo "📊 File size: $(du -h "$MODEL_PATH" | cut -f1)"
        cp "$MODEL_PATH" MacDBG.app/Contents/Resources/models/ 2>/dev/null || true
        echo "🚀 AI features ready!"
    else
        echo "❌ Downloaded file too small - not a real model"
        rm "$MODEL_PATH"
        echo "🔧 Manual download required:"
        echo "   1. Go to: https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
        echo "   2. Download: qwen2.5-coder-3b-instruct-q4_0.gguf"
        echo "   3. Place it at: $MODEL_PATH"
        exit 1
    fi
else
    echo "❌ Download failed - network issue"
    echo "🔧 Manual download required:"
    echo "   1. Go to: https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
    echo "   2. Download: qwen2.5-coder-3b-instruct-q4_0.gguf"
    echo "   3. Place it at: $MODEL_PATH"
    echo "   4. Run: ./build.sh"
    exit 1
fi
