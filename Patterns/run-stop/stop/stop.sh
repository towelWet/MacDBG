#!/bin/bash
# stop.sh - Stop Gemini Web GUI (macOS/Linux version)

# Print info
echo "Stopping Gemini Web GUI servers..."
echo

echo "Looking for running Node.js processes..."

# Get all Node.js PIDs
PIDS=$(pgrep node)

if [ -z "$PIDS" ]; then
  echo "No Node.js processes found."
else
  for PID in $PIDS; do
    # Try to gracefully terminate processes
    echo "Attempting graceful shutdown of PID: $PID"
    kill -SIGINT $PID
  done

  echo "Waiting 3 seconds for graceful shutdown..."
  sleep 3

  # Check if any Node.js processes are still running on ports 3000, 3001, 3002
  for PORT in 3000 3001 3002; do
    PID_ON_PORT=$(lsof -ti tcp:$PORT)
    if [ ! -z "$PID_ON_PORT" ]; then
      echo "Killing process on port $PORT with PID: $PID_ON_PORT"
      kill -9 $PID_ON_PORT
    fi
  done
fi

echo
if pgrep node > /dev/null; then
  echo "Some Node.js processes may still be running."
else
  echo "All servers stopped successfully."
fi

echo
echo "Gemini Web GUI servers have been stopped."
echo "You can now safely close this window."
read -p "Press [Enter] to exit..."
