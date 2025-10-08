#!/bin/bash

# Find the most recent SDK server log files and tail them

LOG_DIR="logs"

if [ ! -d "$LOG_DIR" ]; then
    echo "No logs directory found. Start the SDK server first."
    exit 1
fi

# Find most recent stderr log (where all the [PERMISSION] logs go)
STDERR_LOG=$(ls -t $LOG_DIR/sdk_server_stderr_*.log 2>/dev/null | head -1)

if [ -z "$STDERR_LOG" ]; then
    echo "No log files found in $LOG_DIR/"
    exit 1
fi

echo "Tailing: $STDERR_LOG"
echo "Press Ctrl+C to stop"
echo "=========================================="
tail -f "$STDERR_LOG"
