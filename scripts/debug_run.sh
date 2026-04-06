#!/bin/bash
# Quick debug runner - starts RightLayout with logging and tails the log
# Usage: ./scripts/debug_run.sh

RightLayout_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$HOME/.rightlayout/debug.log"

echo "Building RightLayout..."
cd "$RightLayout_DIR"
swift build || exit 1

# Kill existing
pkill -f ".build/debug/RightLayout" 2>/dev/null || true
sleep 0.3

# Clear log
mkdir -p "$HOME/.rightlayout"
> "$LOG_FILE"

echo "Starting RightLayout with debug logging..."
echo "Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo "---"

# Start RightLayout in background
RightLayout_DEBUG_LOG=1 .build/debug/RightLayout &
RightLayout_PID=$!

cleanup() {
    echo ""
    echo "Stopping RightLayout..."
    kill $RightLayout_PID 2>/dev/null
    exit 0
}
trap cleanup INT TERM

# Tail the log
sleep 1
tail -f "$LOG_FILE"
