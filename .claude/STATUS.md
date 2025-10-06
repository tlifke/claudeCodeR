# RStudio Claude Code Addin - Current Status

## Project Goal
Build an RStudio addin that integrates Claude Code AI assistant with interactive permission handling for tool usage.

## Architecture
- **Python FastAPI server** (`inst/python/sdk_server.py`): Wraps Claude Agent SDK, handles SSE streaming
- **R Shiny UI**: Chat interface in RStudio viewer pane
- **Authentication**: Supports Claude subscription, API key, AWS Bedrock

## Current Status: ✅ WORKING

### What's Working
1. ✅ Python server with ClaudeSDKClient
2. ✅ SDK authentication (Claude subscription, API key, AWS Bedrock)
3. ✅ Streaming text responses
4. ✅ Tool usage (Write, Bash, etc.)
5. ✅ **Interactive permissions** - Modal dialog with approve/deny
6. ✅ Multi-turn conversations
7. ✅ Editor context integration

### Implementation Details
- **Permission Flow**: `callr` background process + file-based IPC + `later::later()` polling
- **SSE Parsing**: Handles CRLF line endings from Python server
- **SDK Patch**: Applied fix for protocol mismatch (see `.claude/SDK_PATCH.md`)

### Known Issues & Workarounds

#### SDK Protocol Mismatch (PATCHED)
**Issue**: SDK v0.1.0 sends `{"allow": true}` but CLI v2.0.5 expects `{"behavior": "allow"}`
**Fix**: Applied patch to `~/.claude-rstudio-venv/lib/python3.10/site-packages/claude_agent_sdk/_internal/query.py`
**Docs**: See `.claude/SDK_PATCH.md` for details
**Tracking**: https://github.com/anthropics/claude-agent-sdk-python/issues/200

#### Claude CLI PATH
**Issue**: Python venv may not have `claude` CLI in PATH
**Fix**: Server adds `~/.npm-global/bin` to PATH at startup (line 192-196 in sdk_server.py)

## Environment
- **Python venv**: `~/.claude-rstudio-venv` (Python 3.10)
- **Claude CLI**: `~/.npm-global/bin/claude` (v2.0.5)
- **R Package**: Uses `system.file("python/sdk_server.py")`

## Quick Test
```r
devtools::load_all()
claude_code_addin()
# Try: "create and run an R script printing hello world"
# ✅ Should show permission modals and execute successfully
```

## Cleanup
Run `.claude/cleanup.sh` to remove unused files:
- Removes `python/.venv` (53MB, unused)
- Removes temp debug logs
- Keeps `~/.claude-rstudio-venv` (76MB, in use)

## Dependencies
**R**: shiny, miniUI, processx, httr, curl, jsonlite, callr, later, rstudioapi
**Python**: claude-agent-sdk (v0.1.0, patched), fastapi, uvicorn, sse-starlette
