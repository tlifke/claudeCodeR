#!/bin/bash
# Get the PID of the SDK server
PID=$(ps aux | grep -i "sdk_server.py" | grep -v grep | awk '{print $2}')

if [ -z "$PID" ]; then
    echo "No SDK server running"
    exit 1
fi

echo "SDK Server PID: $PID"
echo "Checking stderr output..."
echo

# Try to get process info
lsof -p $PID 2>/dev/null | grep -E "(stderr|STDERR|err)"
