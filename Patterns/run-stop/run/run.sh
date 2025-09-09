#!/bin/bash
# Gemini Web GUI Launch Script

echo "Starting Gemini Web GUI..."
echo "Backend: http://localhost:3002"
echo "Frontend: http://localhost:3000 (or 3001 if 3000 is busy)"
echo

# Handle directory argument
if [ -n "$1" ]; then
    if [ -d "$1" ]; then
        export GEMINI_START_DIR="$1"
        echo "Starting directory set to: $1"
    else
        echo "Warning: Provided directory \"$1\" does not exist"
        echo "Will use default starting directory"
    fi
fi

# Cleanup previous processes
echo "Cleaning up any previous runs..."
kill -9 $(lsof -ti :3000) 2>/dev/null
kill -9 $(lsof -ti :3001) 2>/dev/null
kill -9 $(lsof -ti :3002) 2>/dev/null
sleep 1

# Navigate to correct directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CURRENT_DIR="$(pwd)"

if [[ -f "package.json" && -f "server.js" ]]; then
    echo "Found web-gui directory: $CURRENT_DIR"
elif [[ -f "$SCRIPT_DIR/../../packages/web-gui/package.json" ]]; then
    cd "$SCRIPT_DIR/../../packages/web-gui"
    echo "Navigated to web-gui directory: $(pwd)"
elif [[ -f "packages/web-gui/package.json" ]]; then
    cd "packages/web-gui"
    echo "Navigated to web-gui directory: $(pwd)"
else
    echo "Error: Could not find the gemini-gui web-gui directory"
    echo "Script location: $SCRIPT_DIR"
    echo "Current directory: $CURRENT_DIR"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing npm dependencies..."
    npm install --ignore-scripts || { echo "Failed to install dependencies"; exit 1; }
fi

# Start backend server
echo "Starting backend server..."
if [ -n "$GEMINI_START_DIR" ]; then
    PORT=3002 GEMINI_START_DIR="$GEMINI_START_DIR" node server.js &
else
    PORT=3002 node server.js &
fi
BACKEND_PID=$!

sleep 5

# Start frontend server
echo "Starting frontend server..."
npm run dev &
FRONTEND_PID=$!

echo
echo "Both servers are running in the background."
echo "Open http://localhost:3000 in your browser!"
echo "(If port 3000 is busy, frontend will use 3001)"
echo "Backend API is now on port 3002"
echo
echo "Press Ctrl+C to stop servers"

# Wait for termination
trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; exit" SIGINT
wait