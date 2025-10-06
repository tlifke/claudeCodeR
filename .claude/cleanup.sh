#!/bin/bash
# Cleanup script for RStudio Claude Code Addin
# Removes unused Python venv and temporary debug files

echo "🧹 Cleaning up..."

# Remove unused venv
if [ -d "python/.venv" ]; then
    echo "  Removing python/.venv (53MB, unused)..."
    rm -rf python/.venv
    echo "  ✅ Removed"
else
    echo "  ℹ️  python/.venv not found (already clean)"
fi

# Remove temp debug files
echo "  Removing temp debug logs..."
rm -f /tmp/claude_debug.log /tmp/claude_sdk_location.log /tmp/claude_sdk_messages.log
echo "  ✅ Done"

# Keep the working venv
echo ""
echo "📦 Keeping ~/.claude-rstudio-venv (76MB, in use by R)"
echo ""
echo "✨ Cleanup complete!"
echo ""
echo "Note: The SDK patch is documented in .claude/SDK_PATCH.md"
