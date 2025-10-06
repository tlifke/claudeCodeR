# claudeCodeR

Claude Code AI assistant integration for RStudio, powered by the Claude Agent SDK.

## Status

**v0.2.0**: Fully functional implementation using Claude Agent SDK. Tool execution works correctly!

Previous v0.1.0 had architectural issues with tool execution. See [ISSUES.archive.md](ISSUES.archive.md) for historical context.

## Features

- **Claude Code integration**: Full-featured AI coding assistant in RStudio
- **Interactive chat interface**: Clean Shiny gadget UI in RStudio viewer pane
- **Streaming responses**: Real-time response display via Server-Sent Events
- **Editor integration**: Automatic editor context capture and code modifications
- **Multiple auth methods**:
  - Anthropic API key
  - AWS Bedrock (with SSO support)
  - Google Vertex AI (coming soon)
- **Tool execution**: File operations and bash commands work correctly
- **AWS SSO**: Automatic credential validation and refresh prompts

## Architecture

```
RStudio Addin (R)
    ↓ HTTP/SSE
Python FastAPI Server
    ↓
Claude Agent SDK
    ↓
Claude API / AWS Bedrock
```

The addin launches a local Python server that wraps the Claude Agent SDK. The R client communicates with the server via HTTP, and responses stream back via Server-Sent Events (SSE). This architecture solves the async/promise conflicts that plagued v0.1.0.

## Installation

### Prerequisites

1. **RStudio**: Required
2. **Python 3.10+**: Required for Claude Agent SDK
3. **R 4.0+**: Required

### Install R Package

```r
devtools::install_github("yourusername/claudeCodeR")
```

### Python Dependencies (Automatic!)

**No manual setup needed!** The first time you launch the addin, it will:
1. Create a Python virtual environment at `~/.claude-rstudio-venv`
2. Install all required dependencies automatically

This takes about 1 minute on first run, then subsequent launches are instant.

**Requirements**: Python 3.10+ must be installed on your system.

### Authentication Setup

#### Option 1: Claude Subscription (Easiest)

If you have a Claude Pro, Team, or Enterprise subscription and have already authenticated via the `claude` CLI:

**You're done!** The addin will automatically use your existing authentication.

To check if you're authenticated:

```bash
claude auth status
```

If not authenticated, run:

```bash
claude auth login
```

No environment variables needed!

#### Option 2: Anthropic API Key

Add to your `.Renviron`:

```r
usethis::edit_r_environ()
```

Add:

```
ANTHROPIC_API_KEY=your_api_key_here
```

Restart R:

```r
.rs.restartR()
```

#### Option 3: AWS Bedrock

**Step 1**: Enable Bedrock access in AWS console

**Step 2**: Set environment variables in `.Renviron`:

```
CLAUDE_CODE_USE_BEDROCK=1
AWS_REGION=us-east-1
AWS_PROFILE=your-profile-name
```

**Step 3**: Login to AWS SSO (if using SSO):

```bash
aws sso login --profile your-profile-name
```

The addin will automatically prompt you to login if credentials are expired.

**Direct credentials**: If you have `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` set, those will be used instead of SSO.

## Usage

### Launch the Addin

1. In RStudio, go to **Addins** → **Claude Code**
2. If using AWS Bedrock and credentials are expired, you'll be prompted to login via SSO
3. Chat interface will appear in RStudio viewer pane
4. Start chatting!

### Example Prompts

- "Explain this function"
- "Add error handling to the selected code"
- "Write a unit test for this function"
- "Refactor this code to be more efficient"
- "Find bugs in my code"

### Editor Integration

The addin automatically captures:
- Current file path
- File contents
- Selected code (if any)
- Language/syntax

This context is sent with every prompt, so Claude understands what you're working on.

### Code Modifications

When Claude suggests code changes, they can be applied directly to your editor (functionality depends on the specific request and RStudio API capabilities).

## Configuration

### Environment Variables

**Authentication**:
- `ANTHROPIC_API_KEY`: Your Anthropic API key
- `CLAUDE_CODE_USE_BEDROCK`: Set to `1` to use AWS Bedrock

**AWS Bedrock**:
- `AWS_REGION`: AWS region (default: `us-east-1`)
- `AWS_PROFILE`: AWS profile name for SSO
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`: Direct credentials (optional)

**Model Selection (Bedrock)**:
- `ANTHROPIC_MODEL`: Primary model (default: `global.anthropic.claude-sonnet-4-5-20250929-v1:0`)
- `ANTHROPIC_SMALL_FAST_MODEL`: Fast model (default: `us.anthropic.claude-3-5-haiku-20241022-v1:0`)

### Server Configuration

Advanced users can customize:
- `PORT`: Server port (default: `8765`)
- `HOST`: Server host (default: `127.0.0.1`)

Set these before calling the addin (not typically needed).

## Troubleshooting

### "SDK server failed to start"

This usually means Python setup failed. Check:

1. Python 3.10+ is installed: `python3 --version`
2. Delete the venv and try again: `rm -rf ~/.claude-rstudio-venv`
3. Check R console for specific error messages

The venv will be recreated automatically on next launch.

### "Authentication Required" dialog

You need one of:
- Claude CLI authentication (run `claude auth login`), or
- `ANTHROPIC_API_KEY` environment variable, or
- `CLAUDE_CODE_USE_BEDROCK=1` with AWS credentials

See [Authentication Setup](#authentication-setup) above.

### AWS SSO login fails

Make sure `aws` CLI is installed and configured:

```bash
aws configure sso
```

Then test:

```bash
aws sso login --profile your-profile-name
aws sts get-caller-identity
```

### "Session not initialized"

The Python server is having trouble. Check:

1. Python 3.10+ is installed
2. Claude Agent SDK is installed
3. Restart RStudio and try again

### Streaming responses are slow

This is normal for large responses. The SDK streams tokens as they're generated.

For AWS Bedrock users, consider using prompt caching to speed up responses. See [AWS docs](https://aws.amazon.com/blogs/machine-learning/supercharge-your-development-with-claude-code-and-amazon-bedrock-prompt-caching/).

## Development

### Project Structure

```
claudeCodeR/
├── R/
│   ├── addin.R              # Entry point
│   ├── config.R             # Auth detection & server management
│   ├── sdk_client.R         # HTTP client for SDK server
│   ├── shiny_ui.R           # Shiny UI and server
│   └── rstudio_integration.R # RStudio API helpers
├── python/
│   ├── sdk_server.py        # FastAPI server wrapping SDK
│   ├── aws_config.py        # AWS credential helpers
│   ├── pyproject.toml       # Python project config
│   └── requirements.txt     # Python dependencies
├── inst/
│   └── python/              # Bundled Python files
└── DESCRIPTION              # R package metadata
```

### Running Tests

```r
devtools::load_all()
devtools::test()
```

Python tests:

```bash
cd python
pytest
```

### Contributing

Contributions welcome! Please:

1. Fork the repo
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## Migration from v0.1.0

If you were using v0.1.0 (the ACP implementation):

**Breaking changes**:
- No more manual agent type selection (only Claude Code now)
- No more permission mode selector (auto-approved for better UX)
- Python 3.10+ required (was optional before)
- Node.js no longer required (ACP adapter removed)

**What improved**:
- ✅ Tool execution works (file writes, bash commands)
- ✅ Streaming is reliable
- ✅ Better error handling
- ✅ AWS Bedrock support
- ✅ Simpler codebase

## Acknowledgments

- [Claude Agent SDK](https://docs.claude.com/en/api/agent-sdk/overview) by Anthropic
- [FastAPI](https://fastapi.tiangolo.com/) for the Python server framework
- RStudio team for `rstudioapi`

## License

MIT License - see LICENSE file

## Changelog

### v0.2.0 (Current)
- Complete rewrite using Claude Agent SDK
- Tool execution works correctly
- AWS Bedrock support with SSO
- Simplified architecture (HTTP/SSE instead of stdio)
- ~500 lines of code removed

### v0.1.0 (Archived)
- Custom ACP protocol implementation
- Tool execution broken (architectural issue)
- See ISSUES.archive.md for details
