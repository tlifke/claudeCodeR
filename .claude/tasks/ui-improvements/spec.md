# Task: RStudio UI/UX Improvements

## Goal

Solve console blocking issue and add R-specific features (Environment, Console history, Plots) to make claudeCodeR feel native to R users' workflows.

## Success Criteria

- ✅ R console never blocks (can use R while Claude is working)
- ✅ Quick queries available (`claude("explain this")` function)
- ✅ Extended conversations available (full UI)
- ✅ Environment snapshot integration works
- ✅ Plot capture and analysis works
- ✅ User can choose UI mode (browser vs viewer)
- ✅ All existing functionality preserved

## Dependencies

- **External**: None
- **Internal**: SDK or ACP backend working
- **Blocking**: None (can implement alongside backend work)

## Complexity

**Overall**: MEDIUM
- **browserViewer**: TRIVIAL (1-line change)
- **REPL function**: LOW (simple wrapper)
- **Environment integration**: MEDIUM (base R functions)
- **Plot capture**: LOW (rstudioapi)
- **Background process**: HIGH (complex but optional)

## Timeline Estimate

### Quick Wins (Week 1)
- **Phase 1 (browserViewer)**: 1 hour
- **Phase 2 (REPL function)**: 1 day
- **Total**: 1-2 days

### Full Implementation (Week 2-3)
- **Phase 3 (R-specific features)**: 3-5 days
- **Phase 4 (Advanced options)**: 3-5 days (optional)
- **Total**: 2-3 weeks for everything

## Parallelization Strategy

All phases can be developed in parallel:
- **Developer 1**: browserViewer + REPL function
- **Developer 2**: Environment/Plot integration
- **Developer 3**: Background process approach (optional)

## Implementation Plan

### Phase 1: Immediate Fix - browserViewer (1 hour)

#### 1.1 Change Viewer Mode

**File**: `R/addin.R`

**Current**:
```r
shiny::runGadget(ui, server, viewer = shiny::paneViewer(minHeight = 400))
```

**Change to**:
```r
shiny::runGadget(ui, server, viewer = shiny::browserViewer())
```

**That's it!** Console blocking solved.

#### 1.2 Make it Configurable

**File**: `R/config.R`

```r
get_viewer_preference <- function() {
  # Check environment variable
  viewer <- Sys.getenv("CLAUDECODER_VIEWER", "browser")

  if (viewer == "pane") {
    shiny::paneViewer(minHeight = 400)
  } else if (viewer == "dialog") {
    shiny::dialogViewer("Claude Code", width = 1000, height = 800)
  } else {
    shiny::browserViewer()
  }
}
```

**File**: `R/addin.R`

```r
shiny::runGadget(ui, server, viewer = get_viewer_preference())
```

**User can set**:
```r
# In .Renviron
CLAUDECODER_VIEWER=browser  # default
CLAUDECODER_VIEWER=pane     # old behavior
CLAUDECODER_VIEWER=dialog   # floating window
```

**Complexity**: TRIVIAL
**Timeline**: 30 minutes
**Parallelizable**: No (foundation)

---

### Phase 2: REPL Function for Quick Queries (1 day)

#### 2.1 Create claude() Function

**File**: `R/claude_repl.R`

```r
#' Quick Claude Code Query
#'
#' Send a quick query to Claude Code without opening the full UI.
#' Blocks until response received. For extended conversations, use
#' \code{claude_chat()} instead.
#'
#' @param prompt Character string with your query
#' @param context Character: "auto" (default), "selection", "file", or "none"
#' @param execute Logical: if TRUE, automatically execute code blocks (with prompt)
#' @param stream Logical: if TRUE, stream response to console; if FALSE, return silently
#'
#' @return Invisibly returns the response text
#'
#' @examples
#' \dontrun{
#' # Quick inline query
#' claude("how do I remove NA values from a data frame?")
#'
#' # With selection context
#' # 1. Select some code in editor
#' # 2. Run:
#' claude("explain this code", context = "selection")
#'
#' # Get response without printing
#' result <- claude("optimize this function", stream = FALSE)
#' }
#'
#' @export
claude <- function(prompt, context = "auto", execute = FALSE, stream = TRUE) {
  # Start backend if not running
  ensure_backend_running()

  # Get context
  ctx <- get_context_for_repl(context)

  # Build full prompt
  full_prompt <- build_prompt_with_context(prompt, ctx)

  # Send to backend (SDK or ACP)
  if (is_using_sdk()) {
    response <- query_sdk_sync(full_prompt)
  } else {
    response <- query_acp_sync(full_prompt)
  }

  # Stream to console if requested
  if (stream) {
    cat(response, "\n")
  }

  # Extract code blocks
  code_blocks <- extract_code_blocks(response)

  # Offer to execute
  if (execute && length(code_blocks) > 0) {
    for (i in seq_along(code_blocks)) {
      block <- code_blocks[[i]]

      cat("\n--- Code Block", i, "---\n")
      cat(block$code, "\n")

      answer <- readline(prompt = "Execute this code? (y/n): ")

      if (tolower(answer) == "y") {
        eval(parse(text = block$code), envir = .GlobalEnv)
      }
    }
  }

  invisible(response)
}

#' Open Full Claude Code Chat Interface
#'
#' @export
claude_chat <- function() {
  # Launch full Shiny UI
  claude_code_addin()
}
```

#### 2.2 Context Helpers

**File**: `R/context_helpers.R`

```r
get_context_for_repl <- function(context_type) {
  if (!rstudioapi::isAvailable()) {
    return(NULL)
  }

  if (context_type == "none") {
    return(NULL)
  }

  if (context_type == "auto") {
    # Check if there's a selection
    doc_context <- rstudioapi::getActiveDocumentContext()

    if (nchar(doc_context$selection[[1]]$text) > 0) {
      context_type <- "selection"
    } else if (!is.null(doc_context$path) && nchar(doc_context$path) > 0) {
      context_type <- "file"
    } else {
      return(NULL)
    }
  }

  if (context_type == "selection") {
    doc_context <- rstudioapi::getActiveDocumentContext()
    selection <- doc_context$selection[[1]]$text

    return(list(
      type = "selection",
      path = doc_context$path,
      content = selection,
      language = "r"
    ))
  }

  if (context_type == "file") {
    doc_context <- rstudioapi::getActiveDocumentContext()

    return(list(
      type = "file",
      path = doc_context$path,
      content = paste(doc_context$contents, collapse = "\n"),
      language = "r"
    ))
  }

  NULL
}

extract_code_blocks <- function(text) {
  # Regex to find ```r ... ``` blocks
  pattern <- "```r\\s*\\n(.*?)\\n```"
  matches <- gregexpr(pattern, text, perl = TRUE)

  if (matches[[1]][1] == -1) {
    return(list())
  }

  blocks <- list()
  match_data <- matches[[1]]
  match_lengths <- attr(match_data, "match.length")

  for (i in seq_along(match_data)) {
    start <- match_data[i]
    length <- match_lengths[i]
    block_text <- substr(text, start, start + length - 1)

    # Extract code between ```r and ```
    code <- gsub("```r\\s*\\n|\\n```", "", block_text)

    blocks[[i]] <- list(
      code = code,
      start = start,
      length = length
    )
  }

  blocks
}
```

#### 2.3 Backend Helpers

**File**: `R/backend_manager.R`

```r
.backend_state <- new.env(parent = emptyenv())
.backend_state$process <- NULL
.backend_state$type <- NULL  # "sdk" or "acp"

ensure_backend_running <- function() {
  if (is_backend_running()) {
    return(TRUE)
  }

  # Detect which backend to use
  if (file.exists("python/sdk_server.py")) {
    start_sdk_backend()
    .backend_state$type <- "sdk"
  } else if (Sys.which("websocketd") != "") {
    start_acp_backend()
    .backend_state$type <- "acp"
  } else {
    stop("No backend available. Install Python SDK or websocketd.")
  }

  TRUE
}

is_backend_running <- function() {
  if (is.null(.backend_state$process)) {
    return(FALSE)
  }

  .backend_state$process$is_alive()
}

is_using_sdk <- function() {
  .backend_state$type == "sdk"
}

query_sdk_sync <- function(prompt) {
  client <- ClaudeSDKClient$new()

  # Initialize if needed
  if (!client$is_initialized()) {
    initialize_session(client, getwd(), detect_auth_method())
  }

  # Query (blocking)
  response_text <- ""

  query_streaming(
    client,
    prompt = prompt,
    on_text = function(text) {
      cat(text)
      response_text <<- paste0(response_text, text)
    }
  )

  response_text
}
```

**Complexity**: MEDIUM
**Timeline**: 6-8 hours
**Parallelizable**: Yes (after Phase 1)

---

### Phase 3: R-Specific Features (3-5 days)

#### 3.1 Environment Snapshot

**File**: `R/environment_helpers.R`

```r
#' Get Environment Snapshot
#'
#' Captures current state of R global environment for sending to Claude
#'
#' @param max_objects Maximum number of objects to include
#' @param max_size Maximum size per object (in bytes)
#' @param include_preview Include str() preview?
#'
#' @return List with environment information
#'
#' @export
get_environment_snapshot <- function(max_objects = 50, max_size = 1e6, include_preview = TRUE) {
  env_names <- ls(envir = .GlobalEnv)

  if (length(env_names) == 0) {
    return(list(message = "Environment is empty"))
  }

  if (length(env_names) > max_objects) {
    env_names <- head(env_names, max_objects)
    truncated <- TRUE
  } else {
    truncated <- FALSE
  }

  objects <- lapply(setNames(env_names, env_names), function(name) {
    tryCatch({
      obj <- get(name, envir = .GlobalEnv)
      obj_size <- as.numeric(object.size(obj))

      info <- list(
        name = name,
        class = class(obj)[1],
        type = typeof(obj),
        size = format(object.size(obj), units = "auto")
      )

      # Add dimensions for arrays/data frames
      if (!is.null(dim(obj))) {
        info$dim <- dim(obj)
      } else {
        info$length <- length(obj)
      }

      # Add preview if requested and object not too large
      if (include_preview && obj_size < max_size) {
        preview <- capture.output(str(obj, max.level = 1, vec.len = 2))
        info$preview <- paste(preview, collapse = "\n")
      }

      info
    }, error = function(e) {
      list(
        name = name,
        error = e$message
      )
    })
  })

  list(
    objects = objects,
    count = length(env_names),
    truncated = truncated
  )
}

#' Format Environment for Claude
#'
#' @param snapshot Output from get_environment_snapshot()
#' @return Formatted text for sending to Claude
format_environment_for_claude <- function(snapshot) {
  if (!is.null(snapshot$message)) {
    return(snapshot$message)
  }

  lines <- c("## Current R Environment\n")

  for (obj in snapshot$objects) {
    if (!is.null(obj$error)) {
      lines <- c(lines, sprintf("- **%s**: Error: %s", obj$name, obj$error))
      next
    }

    # Basic info
    info_parts <- c(obj$class)

    if (!is.null(obj$dim)) {
      info_parts <- c(info_parts, sprintf("dim: [%s]", paste(obj$dim, collapse = ", ")))
    } else if (!is.null(obj$length)) {
      info_parts <- c(info_parts, sprintf("length: %d", obj$length))
    }

    info_parts <- c(info_parts, obj$size)

    lines <- c(lines, sprintf("- **%s**: %s", obj$name, paste(info_parts, collapse = ", ")))

    # Preview if available
    if (!is.null(obj$preview)) {
      lines <- c(lines, "  ```")
      lines <- c(lines, paste("  ", strsplit(obj$preview, "\n")[[1]]))
      lines <- c(lines, "  ```")
    }
  }

  if (snapshot$truncated) {
    lines <- c(lines, sprintf("\n*(Showing first %d objects)*", snapshot$count))
  }

  paste(lines, collapse = "\n")
}
```

**UI Integration**:

```r
# In Shiny UI
checkboxInput("include_env", "Include Environment", value = FALSE)

# In server
build_prompt_with_context <- function(prompt) {
  parts <- list(prompt)

  # Editor context
  if (has_editor_context()) {
    parts <- c(get_editor_context_text(), parts)
  }

  # Environment context
  if (input$include_env) {
    env_snapshot <- get_environment_snapshot()
    env_text <- format_environment_for_claude(env_snapshot)
    parts <- c(env_text, parts)
  }

  paste(parts, collapse = "\n\n")
}
```

**Complexity**: MEDIUM
**Timeline**: 1-2 days
**Parallelizable**: Yes

---

#### 3.2 Plot Capture

**File**: `R/plot_helpers.R`

```r
#' Capture Current Plot
#'
#' Saves the currently displayed plot to a temporary file
#'
#' @param width Width in pixels (default: 800)
#' @param height Height in pixels (default: 600)
#' @param dpi DPI for image (default: 96)
#'
#' @return Path to saved image file, or NULL if no plot
#'
#' @export
capture_current_plot <- function(width = 800, height = 600, dpi = 96) {
  if (!rstudioapi::isAvailable()) {
    return(NULL)
  }

  temp_file <- tempfile(fileext = ".png")

  tryCatch({
    rstudioapi::savePlotAsImage(
      temp_file,
      width = width,
      height = height,
      dpi = dpi
    )

    if (file.exists(temp_file)) {
      return(temp_file)
    } else {
      return(NULL)
    }
  }, error = function(e) {
    warning("Failed to capture plot: ", e$message)
    NULL
  })
}

#' Analyze Current Plot with Claude
#'
#' Captures the current plot and asks Claude to analyze it
#'
#' @param prompt Optional custom prompt (default: "Analyze this plot")
#' @param include_code Include plot generation code if available
#'
#' @export
claude_analyze_plot <- function(prompt = "Analyze this plot and suggest improvements", include_code = TRUE) {
  plot_file <- capture_current_plot()

  if (is.null(plot_file)) {
    stop("No plot to analyze. Create a plot first.")
  }

  # Build prompt
  full_prompt <- prompt

  if (include_code) {
    # Try to get recent plot commands from history
    # (Note: .Rhistory parsing is fragile, this is a simple attempt)
    history_lines <- tryCatch({
      tail(readLines("~/.Rhistory"), 50)
    }, error = function(e) character(0))

    # Look for plotting commands
    plot_commands <- grep("^(plot|ggplot|hist|barplot|boxplot)", history_lines, value = TRUE)

    if (length(plot_commands) > 0) {
      code_context <- paste("Recent plotting code:", "",
                           paste("```r", paste(plot_commands, collapse = "\n"), "```", sep = "\n"),
                           sep = "\n")
      full_prompt <- paste(code_context, full_prompt, sep = "\n\n")
    }
  }

  # TODO: Send image to Claude (requires vision API support)
  # For now, just describe that there's a plot
  full_prompt <- paste(
    full_prompt,
    sprintf("\n(Plot saved to: %s)", plot_file),
    sep = "\n"
  )

  # Query Claude
  claude(full_prompt, context = "none")
}
```

**Future**: When Claude API supports vision, send the actual image:
```r
# Encode image as base64
plot_base64 <- base64enc::base64encode(plot_file)

# Send to Claude with vision
# (Requires SDK/ACP support for image attachments)
```

**Complexity**: LOW-MEDIUM
**Timeline**: 4-6 hours
**Parallelizable**: Yes

---

#### 3.3 Console History (Skip for Now)

**Recommendation**: **Do NOT implement** console history parsing

**Reasons**:
1. No official `rstudioapi` support
2. `.Rhistory` parsing is fragile
3. Privacy concerns
4. Low value vs. risk

**Alternative**: User can manually paste relevant history into prompt

**Complexity**: N/A
**Timeline**: N/A

---

### Phase 4: Advanced Options (3-5 days, OPTIONAL)

#### 4.1 Background Process Approach

**Only pursue if**:
- Viewer pane integration is critical
- Users strongly prefer integrated UI
- browserViewer not acceptable

**Architecture**:
```
Main R Session (RStudio)
    ↓ IPC (files or sockets)
Background R Session (callr::r_bg)
    ↓ Shiny in background
    ↓ HTTP or WebSocket
Backend (SDK or ACP)
```

**File**: `R/background_gadget.R`

```r
claude_code_addin_background <- function() {
  # Start background R process with Shiny
  bg_proc <- callr::r_bg(
    function() {
      library(claudeCodeR)
      # Run Shiny app
      shiny::runGadget(
        claude_ui(),
        claude_server(),
        viewer = shiny::paneViewer()
      )
    },
    supervise = TRUE
  )

  # Monitor IPC for requests from background
  ipc_monitor <- later::later(function() {
    # Check for IPC messages
    # Respond with rstudioapi data
  }, delay = 0.1, loop = TRUE)

  # Return handle
  list(
    process = bg_proc,
    ipc_monitor = ipc_monitor
  )
}
```

**Challenges**:
- IPC complexity
- rstudioapi only works in main process
- Process lifecycle management
- Debugging difficulty

**Complexity**: HIGH
**Timeline**: 1-2 weeks
**Parallelizable**: No (complex)

**Recommendation**: **Defer** until user feedback shows strong need

---

#### 4.2 Keyboard Shortcuts

**File**: `R/addins.R` (or separate addin entries)

```r
# .rs.registerCommand("claude-quick-query", function() {
#   # Get selection or current line
#   # Run claude() with it
# })

# Bind to Cmd+Shift+C or similar
```

**File**: `inst/rstudio/addins.dcf`

```dcf
Name: Claude Quick Query
Description: Send selection to Claude
Binding: claude_quick_query
Interactive: false

Name: Claude Explain
Description: Explain selected code
Binding: claude_explain_selection
Interactive: false

Name: Claude Optimize
Description: Optimize selected code
Binding: claude_optimize_selection
Interactive: false
```

**Complexity**: LOW
**Timeline**: 2-3 hours
**Parallelizable**: Yes

---

## Testing Requirements

### Unit Tests

**R tests** (`tests/testthat/test-ui.R`):
```r
test_that("get_viewer_preference works", {
  # Test different CLAUDECODER_VIEWER values
})

test_that("claude() function works", {
  # Mock backend
  # Call claude()
  # Verify response
})

test_that("get_environment_snapshot works", {
  # Create test environment
  # Get snapshot
  # Verify format
})

test_that("capture_current_plot works", {
  # Create plot
  # Capture
  # Verify file exists
})
```

### Manual Testing

- [ ] browserViewer solves console blocking
- [ ] claude() function works for quick queries
- [ ] Environment snapshot captures correctly
- [ ] Environment snapshot formats nicely
- [ ] Plot capture works
- [ ] Plot analysis prompt includes context
- [ ] Keyboard shortcuts work
- [ ] All viewers work (browser, pane, dialog)

## Risks & Mitigation

### Risk 1: Users Prefer Pane Viewer
**Probability**: MEDIUM
**Impact**: LOW
**Mitigation**: Make it configurable, default to browser but allow pane

### Risk 2: Environment Snapshot Too Large
**Probability**: LOW
**Impact**: MEDIUM
**Mitigation**: Limit to 50 objects, skip large objects, add truncation

### Risk 3: Plot Capture Fails
**Probability**: LOW
**Impact**: LOW
**Mitigation**: Graceful error handling, clear user message

## Success Verification

### Automated
- [ ] All unit tests pass
- [ ] No console blocking in any mode
- [ ] Performance acceptable

### Manual
- [ ] User workflow feels natural
- [ ] R-specific features useful
- [ ] No crashes or hangs
- [ ] Documentation clear

## Deliverables

1. **browserViewer** as default (console never blocks)
2. **claude()** function for quick queries
3. **Environment integration** (snapshot + format)
4. **Plot capture** (save + analyze)
5. **Configuration options** (viewer preference)
6. **Documentation** (examples of each feature)
7. **Keyboard shortcuts** (optional)

## Next Steps After Completion

1. Gather user feedback
2. Iterate on UX based on real usage
3. Consider advanced features (background process) if needed
4. Explore additional R-specific integrations (code coverage, profiling, etc.)
