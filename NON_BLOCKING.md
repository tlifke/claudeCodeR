# Non-Blocking UI Mode

## Problem

The original implementation uses `shiny::runGadget()` which **always blocks** the R console, even when using `browserViewer()`. The viewer parameter only controls WHERE the UI displays, not whether it blocks the console.

## Solution

Run the Shiny app in a **background R process** using `callr::r_bg()`. This allows:
- ✅ R console remains free while app is running
- ✅ Browser opens with the app
- ✅ Can use R normally while chatting with Claude
- ✅ App runs until manually stopped

## Usage

### Default (Non-Blocking)

```r
# Launch in background - console stays free
claudeCodeR::claude_code_addin()

# Use R normally while app is running
x <- 1:10
plot(x)

# Stop the app when done
claude_code_stop()
```

### Blocking Mode (Old Behavior)

If you prefer the old blocking behavior:

```r
# Option 1: Pass argument
claude_code_addin(background = FALSE)

# Option 2: Set environment variable
Sys.setenv(CLAUDECODER_MODE = "blocking")
claude_code_addin()  # Will use blocking mode
```

## How It Works

### Background Mode (Default)

1. `claude_code_addin()` starts a background R process via `callr::r_bg()`
2. That process:
   - Starts the Python SDK server
   - Starts the Shiny app on port 3838
   - Keeps both running
3. Main R session:
   - Opens browser to `http://localhost:3838`
   - Returns immediately
   - Console is free to use
4. Stop with `claude_code_stop()` or close the browser tab

### Blocking Mode (Optional)

1. `claude_code_addin(background = FALSE)` runs normally
2. Uses `shiny::runGadget()` with `browserViewer()`
3. Browser opens but **console blocks**
4. Console frees when you close the app

## Configuration

Set environment variable in `.Renviron`:

```bash
# Non-blocking (default)
CLAUDECODER_MODE=background

# Blocking (old behavior)
CLAUDECODER_MODE=blocking
```

## Functions

### `claude_code_addin(background = TRUE)`

Main entry point. Launches Claude Code UI.

**Parameters**:
- `background`: Logical. If `TRUE`, runs in background (non-blocking). If `FALSE`, runs in foreground (blocking). Default: `TRUE`.

### `claude_code_stop()`

Stops the background Claude Code process.

Only works if app was launched in background mode.

## Trade-offs

### Background Mode ✅ (Recommended)

**Pros**:
- Console never blocks
- Can use R while chatting
- More natural workflow

**Cons**:
- Must remember to stop with `claude_code_stop()`
- Uses separate R process (small memory overhead)
- Takes ~3 seconds to start up

### Blocking Mode

**Pros**:
- Simpler model (runs, then stops)
- No manual cleanup needed
- Slightly faster startup

**Cons**:
- Console blocked until closed
- Can't use R while app is open
- Interrupts workflow

## Troubleshooting

### "Background process failed"

Check that:
1. Port 3838 is available: `system("lsof -i :3838")`
2. Python SDK is working: Try blocking mode first
3. Check process output:
   ```r
   proc <- .GlobalEnv$.claude_code_process
   proc$read_output()
   proc$read_error()
   ```

### Process won't stop

```r
# Force kill
if (exists(".claude_code_process", envir = .GlobalEnv)) {
  proc <- .GlobalEnv$.claude_code_process
  proc$kill()
  rm(".claude_code_process", envir = .GlobalEnv)
}
```

### Port already in use

Change the port in `addin_nonblocking.R`:
```r
app_port <- 3839  # Or any free port
```

## Implementation Details

The background mode uses:
- `callr::r_bg()` to spawn background R process
- `shiny::shinyApp()` instead of `shiny::runGadget()`
- `utils::browseURL()` to open browser
- Global variable `.claude_code_process` to track the process

See `R/addin_nonblocking.R` for full implementation.
