#!/bin/bash

AGENT=${1:-claude}
PORT=${2:-8766}

if [ "$AGENT" = "claude" ]; then
    COMMAND="npx --yes @zed-industries/claude-code-acp"
elif [ "$AGENT" = "gemini" ]; then
    COMMAND="npx --yes @google/gemini-cli --experimental-acp"
else
    echo "Unknown agent: $AGENT"
    echo "Usage: $0 [claude|gemini] [port]"
    exit 1
fi

WEBSOCKETD=$(command -v websocketd)
if [ -z "$WEBSOCKETD" ]; then
    WEBSOCKETD="$HOME/.claude-rstudio/bin/websocketd"
    if [ ! -f "$WEBSOCKETD" ]; then
        echo "websocketd not found in PATH or ~/.claude-rstudio/bin/"
        echo "Please install websocketd first"
        exit 1
    fi
fi

echo "Starting $AGENT agent on port $PORT..."
echo "WebSocket URL: ws://localhost:$PORT"
echo "Dev console: http://localhost:$PORT"
echo ""
echo "Command: $WEBSOCKETD --port=$PORT --devconsole $COMMAND"
echo ""

exec "$WEBSOCKETD" --port="$PORT" --devconsole $COMMAND
