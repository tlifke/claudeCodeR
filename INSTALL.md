# Installation Guide

## Prerequisites

### 1. RStudio
This package requires RStudio IDE. Download from [rstudio.com](https://www.rstudio.com/products/rstudio/download/).

### 2. R Packages
The following R packages will be installed automatically:
- processx
- jsonlite
- promises
- later
- shiny
- miniUI
- rstudioapi
- R6

### 3. Node.js (for Claude Code)
If you plan to use Claude Code, install Node.js from [nodejs.org](https://nodejs.org/).

### 4. API Keys
You'll need an API key for your chosen agent:
- **Claude Code**: Get an Anthropic API key from [console.anthropic.com](https://console.anthropic.com/)
- **Gemini CLI**: Get a Google AI API key from [makersuite.google.com](https://makersuite.google.com/)

## Installation Steps

### Step 1: Install the R Package

```r
install.packages("devtools")
devtools::install_github("yourusername/claudeACP")
```

### Step 2: Install Agent Dependencies

#### For Claude Code:
```bash
npm install -g @zed-industries/claude-code-acp
```

Verify installation:
```bash
npx @zed-industries/claude-code-acp --help
```

#### For Gemini CLI:
Follow the installation instructions at the [Gemini CLI repository](https://github.com/google/gemini-cli).

### Step 3: Configure API Keys

Create or edit your `.Renviron` file:

```r
usethis::edit_r_environ()
```

Add your API key(s):
```bash
ANTHROPIC_API_KEY=sk-ant-your-key-here
GEMINI_API_KEY=your-gemini-key-here
```

Save the file and restart R:
```r
.rs.restartR()
```

Verify your keys are loaded:
```r
Sys.getenv("ANTHROPIC_API_KEY")
```

### Step 4: Test the Installation

```r
library(claudeACP)

claude_acp_addin()
```

You should see the Claude ACP Agent dialog appear. Select your agent from the dropdown and start chatting!

## Troubleshooting

### "Agent not ready" error
- Ensure your API key is correctly set in `.Renviron`
- Verify Node.js and the ACP adapter are installed
- Check that the agent process can start:
  ```bash
  ANTHROPIC_API_KEY=your-key npx @zed-industries/claude-code-acp
  ```

### "RStudio API not available" error
- This package only works in RStudio IDE
- Ensure you're running a recent version of RStudio (>= 1.4)

### Package dependency issues
```r
install.packages(c("processx", "jsonlite", "promises", "later", "shiny", "miniUI", "rstudioapi", "R6"))
```

### Node.js not found
- Ensure Node.js is installed and in your PATH
- Restart RStudio after installing Node.js

## Upgrading

To update to the latest version:

```r
devtools::install_github("yourusername/claudeACP", force = TRUE)
```

## Uninstallation

```r
remove.packages("claudeACP")
```

Also remove the agent dependencies if no longer needed:
```bash
npm uninstall -g @zed-industries/claude-code-acp
```
