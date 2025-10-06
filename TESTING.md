# Testing Guide

## Manual Testing

### Prerequisites
- RStudio installed
- Node.js installed
- `@zed-industries/claude-code-acp` installed globally
- `ANTHROPIC_API_KEY` set in `.Renviron`

### Test Suite

#### 1. Package Installation
```r
devtools::load_all()
```
**Expected**: Package loads without errors

#### 2. Launch Addin
```r
claudeACP::claude_acp_addin()
```
**Expected**: Shiny gadget dialog appears with chat interface

#### 3. Agent Initialization (Claude Code)
1. Select "Claude Code" from agent dropdown
2. Wait for initialization

**Expected**:
- System message: "Agent initialized successfully"
- System message: "Session created. Ready to assist!"

#### 4. Send Simple Prompt
```
Write a function that adds two numbers
```
**Expected**:
- Response streams in (shows agent typing)
- Code appears in agent message box
- No errors in R console

#### 5. Code Insertion
```
Add a comment to the current line explaining what it does
```
**Expected**:
- Code is inserted at cursor position in active document
- Or prompt to select a document if none active

#### 6. Context Awareness
Open an R file and send:
```
Refactor the current function to be more readable
```
**Expected**:
- Agent reads the active document
- Provides relevant suggestions based on actual code

#### 7. Permission Requests
```
Read the contents of my DESCRIPTION file
```
**Expected**:
- Permission dialog appears
- Grant/Deny buttons work
- File is read if granted

#### 8. Session Management
1. Have a conversation with multiple prompts
2. Close and reopen the addin
3. Check if history persists (if session/load is implemented)

#### 9. Gemini CLI (if available)
1. Set `GEMINI_API_KEY` in `.Renviron`
2. Install Gemini CLI
3. Select "Gemini CLI" from dropdown
4. Send a prompt

**Expected**: Works similarly to Claude Code

#### 10. Error Handling
Test without API key:
```r
Sys.unsetenv("ANTHROPIC_API_KEY")
claudeACP::claude_acp_addin()
```
**Expected**: Graceful error message

### Programmatic Testing

```r
library(claudeACP)

test_client_creation <- function() {
  client <- ACPClient$new(
    command = "npx",
    args = c("@zed-industries/claude-code-acp"),
    env = c(paste0("ANTHROPIC_API_KEY=", Sys.getenv("ANTHROPIC_API_KEY")))
  )

  stopifnot(!is.null(client))
  stopifnot(!is.null(client$process))
  stopifnot(client$process$is_alive())

  client$shutdown()
  print("✓ Client creation test passed")
}

test_initialization <- function() {
  client <- ACPClient$new(
    command = "npx",
    args = c("@zed-industries/claude-code-acp"),
    env = c(paste0("ANTHROPIC_API_KEY=", Sys.getenv("ANTHROPIC_API_KEY")))
  )

  setup_client_methods(client)

  promises::then(
    client$initialize_agent(list(name = "Test", version = "1.0.0")),
    onFulfilled = function(result) {
      stopifnot(!is.null(result))
      print("✓ Initialization test passed")
      client$shutdown()
    },
    onRejected = function(error) {
      stop("Initialization failed: ", error$message)
    }
  )
}

test_session_creation <- function() {
  client <- ACPClient$new(
    command = "npx",
    args = c("@zed-industries/claude-code-acp"),
    env = c(paste0("ANTHROPIC_API_KEY=", Sys.getenv("ANTHROPIC_API_KEY")))
  )

  setup_client_methods(client)

  promises::then(
    client$initialize_agent(list(name = "Test", version = "1.0.0")),
    onFulfilled = function(init_result) {
      promises::then(
        client$create_session(),
        onFulfilled = function(session_result) {
          stopifnot(!is.null(session_result$session_id))
          print("✓ Session creation test passed")
          client$shutdown()
        }
      )
    }
  )
}

run_all_tests <- function() {
  test_client_creation()
  Sys.sleep(1)
  test_initialization()
  Sys.sleep(1)
  test_session_creation()
  print("\n✓ All tests passed!")
}
```

## Known Limitations

1. **Async Testing**: R's promises can be tricky to test synchronously
2. **UI Testing**: Shiny gadgets require manual testing
3. **Agent Availability**: Tests require working agent installations
4. **API Keys**: Tests require valid API keys

## Debugging

### Enable Verbose Logging

```r
options(claudeACP.debug = TRUE)
```

### Check Process Output

```r
client <- ACPClient$new(...)
Sys.sleep(2)
stderr_output <- client$process$read_error_lines()
print(stderr_output)
```

### Inspect Messages

Add debug prints in `acp_client.R`:
```r
private$handle_message = function(msg) {
  print("Received message:")
  print(msg)

}
```

## Continuous Integration

For automated testing (future):

```yaml
name: R-CMD-check

on: [push, pull_request]

jobs:
  R-CMD-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: r-lib/actions/setup-r@v2
      - name: Install dependencies
        run: |
          install.packages("remotes")
          remotes::install_deps(dependencies = TRUE)
      - name: Check package
        run: rcmdcheck::rcmdcheck(args = "--no-manual", error_on = "error")
```

Note: Full integration tests require API keys and should use secrets in CI.

## Reporting Issues

When reporting bugs, include:
1. R version: `R.version.string`
2. RStudio version: `RStudio.Version()$version`
3. Package version: `packageVersion("claudeACP")`
4. Agent type and version
5. Full error message and traceback
6. Steps to reproduce
