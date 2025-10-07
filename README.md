# claudeCodeR

Claude Code AI assistant integration for RStudio, powered by the Claude Agent SDK.

## Quick Start

### Installation

```r
# Install from GitHub
install.packages("remotes")  # if not already installed
remotes::install_github("tlifke/claudeCodeR")
```

### Setup

1. **Authentication** - Choose one:
   - **Option 1 (Recommended)**: Use Claude CLI if you have a Claude Pro/Team subscription
     ```bash
     claude auth login
     ```
   - **Option 2**: Set API key in `.Renviron`
     ```r
     usethis::edit_r_environ()
     # Add: ANTHROPIC_API_KEY=your_api_key_here
     # Restart R
     ```

2. **Launch the addin**:
   - RStudio → Addins → "Claude Code"
   - First launch automatically sets up Python environment (takes ~1 minute)
   - Subsequent launches are instant

3. **Start chatting!**
   - The chat interface appears in the RStudio viewer pane
   - Ask Claude to explain, refactor, debug, or write code

## Main Function

**Use `claude_code_addin()` for all functionality.** This is the fully-featured, recommended interface.

```r
library(claudeCodeR)
# Or just use: RStudio → Addins → "Claude Code"
```

> **Note**: This package also includes experimental ACP-based alternatives (`claude_code_acp_addin()`), but these have limited features and are not recommended for regular use.

## Features

- ✅ **Multi-turn conversations** - Full context memory across messages
- ✅ **Tool execution** - File operations and bash commands work correctly
- ✅ **Streaming responses** - Real-time display via Server-Sent Events
- ✅ **Editor integration** - Automatic context capture from your active file
- ✅ **Code modifications** - Claude can directly edit your code
- ✅ **Multiple auth methods** - Claude CLI or API key

## Requirements

- RStudio
- R 4.0+
- Python 3.10+ (for Claude Agent SDK)
- One of:
  - Claude Pro/Team/Enterprise subscription, or
  - Anthropic API key

## Architecture

```
RStudio Addin (R)
    ↓ HTTP/SSE
Python FastAPI Server
    ↓
Claude Agent SDK
    ↓
Claude API
```

The package launches a local Python server that wraps the Claude Agent SDK. R communicates via HTTP with streaming responses via Server-Sent Events.

## Example Prompts

- "Explain this function"
- "Add error handling to the selected code"
- "Write a unit test for this function"
- "Refactor this code to be more efficient"
- "Find bugs in my code"

## Troubleshooting

### "SDK server failed to start"

Check Python version and try resetting the environment:
```bash
python3 --version  # Should be 3.10+
rm -rf ~/.claude-rstudio-venv
```

Then restart the addin - it will recreate the environment.

### "Authentication Required"

You need either:
- Claude CLI authentication (`claude auth login`), or
- `ANTHROPIC_API_KEY` environment variable

### Python environment issues

The package automatically creates a virtual environment at `~/.claude-rstudio-venv` on first launch. If you have issues, delete this directory and try again.

## Advanced Configuration

### Environment Variables

Set in `.Renviron`:
```
ANTHROPIC_API_KEY=your_key_here
ANTHROPIC_MODEL=claude-sonnet-4-5-20250929  # Optional: specify model
```

### Server Settings

Advanced users can customize (usually not needed):
```r
Sys.setenv(PORT = "8765")   # Server port
Sys.setenv(HOST = "127.0.0.1")  # Server host
```

## Development

### Project Structure

```
claudeCodeR/
├── R/
│   ├── addin.R              # Main entry point
│   ├── config.R             # Auth & server management
│   ├── sdk_client.R         # HTTP client for SDK server
│   ├── shiny_ui.R           # Shiny UI
│   └── acp_*.R              # Experimental ACP implementation
├── python/
│   └── sdk_server.py        # FastAPI server wrapping SDK
└── inst/
    └── python/              # Bundled Python files
```

### Running from Source

```r
devtools::load_all()
claude_code_addin()
```

## Contributing

Contributions welcome! Please:

1. Fork the repo
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## Version History

### v0.2.0 (Current)
- ✅ Multi-turn conversations with full context memory
- ✅ Persistent SDK client for reliable session handling
- ✅ Tool execution works correctly (file writes, bash commands)
- ✅ Streaming responses via SSE
- ✅ Simplified architecture using Claude Agent SDK

### v0.1.0 (Archived)
- Custom ACP protocol implementation
- Had architectural issues with tool execution
- See ISSUES.archive.md for details

## Acknowledgments

- [Claude Agent SDK](https://docs.claude.com/en/api/agent-sdk/overview) by Anthropic
- [FastAPI](https://fastapi.tiangolo.com/) for the Python server
- RStudio team for `rstudioapi`

## License

MIT License - see LICENSE file
