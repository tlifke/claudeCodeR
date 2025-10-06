# Quick Start Guide

## Current State

This package has a **working chat interface** but tool execution (file writes, bash commands) doesn't complete yet.

## Installation

```r
devtools::install_local("/Users/tylerlifke/Documents/r-studio-claude-code-addin")
```

## Prerequisites

1. RStudio installed
2. Node.js installed
3. Claude Code ACP adapter:
   ```bash
   npm install -g @zed-industries/claude-code-acp
   ```

## Usage

### Launch the Chat Interface

```r
library(claudeACP)
claude_acp_addin()
```

This opens a chat interface in the RStudio viewer pane where you can:
- Ask Claude questions
- See streaming responses
- View permission requests (auto-approved)

### What Works

- ✅ Chat conversation
- ✅ Streaming responses
- ✅ Permission auto-approval
- ✅ RStudio viewer pane integration

### What Doesn't Work

- ❌ File creation/editing
- ❌ Bash command execution
- ❌ Tool calls in general

## Alternative: Terminal Integration (Recommended for Now)

For full functionality, use Claude Code directly in RStudio's terminal:

1. Open Terminal in RStudio (Tools → Terminal → New Terminal)
2. Run: `claude`
3. Use Claude Code normally with full tool support

## Testing

Run handler tests to verify the core components work:

```r
source("test_handlers.R")
```

Expected output:
```
Write handler: PASS
Permission handler: PASS
```

## Troubleshooting

### "Agent not ready" error
- Check that `claude-code-acp` is installed: `npx @zed-industries/claude-code-acp --help`
- Verify Node.js is in your PATH

### R session crashes
- This was an earlier issue, should be resolved
- If it happens, check [ISSUES.md](ISSUES.md) for details

### Permissions not working
- Permissions are auto-approved, you should see "Responding: allow_always" in console
- Check console output for permission request logs

## Next Steps

See [ISSUES.md](ISSUES.md) for:
- Detailed technical analysis
- Known issues
- Potential solutions
- Architecture notes

## Contributing

This is an experimental package. The main blocker is making ACP's synchronous request-response pattern work with Shiny's async event loop.

If you have ideas or want to help debug, check the issues list and add detailed logging to `R/acp_client.R`.
