# Task: ACP + WebSocket Integration

## Goal

Implement Agent Client Protocol (ACP) support using a WebSocket proxy layer (websocketd or similar) to enable multi-agent support (Claude, Gemini, GitHub Copilot) while avoiding stdio blocking issues in Shiny.

## Key Insight

**The WebSocket Solution**: Instead of stdio directly from Shiny (which blocks), use a WebSocket proxy:

```
R Shiny Gadget
    ↓ WebSocket (async, non-blocking!)
websocketd process
    ↓ stdio (blocking, but isolated in separate process)
ACP Agent (claude-code-acp, gemini-cli, etc.)
```

This is **exactly how marimo solves the problem** in their React implementation.

## Why This Approach?

### Advantages over Current SDK Approach

1. **Multi-Agent Support** ⭐⭐⭐
   - Support ANY ACP-compatible agent (Claude, Gemini, GitHub, custom)
   - User can switch between providers
   - Not locked to Anthropic API

2. **Simpler Architecture**
   - No Python FastAPI server needed
   - `websocketd` handles all proxying
   - Just spawn as background process

3. **Less Code to Maintain**
   - ~200 lines vs ~500 lines (Python server + R client)
   - No SDK version tracking
   - Protocol handles versioning

4. **Open Ecosystem**
   - ACP is growing (Zed, marimo, Neovim, Emacs)
   - Community-driven improvements
   - Future-proof

### Why We Didn't Use This Before (v0.1.0)

**v0.1.0 tried stdio directly**: R → stdio → ACP agent
- **Result**: Deadlock due to synchronous permissions blocking Shiny

**Now we know**: R → WebSocket → websocketd → stdio → ACP agent
- **Result**: WebSocket is async, no blocking!

### Compared to SDK Approach

| Aspect | SDK (Current) | ACP + WebSocket |
|--------|---------------|-----------------|
| **Agents** | Claude only | Any ACP agent |
| **Architecture** | R → Python → SDK → API | R → WebSocket → ACP |
| **Code** | ~500 lines | ~200 lines |
| **Dependencies** | Python, FastAPI, uvicorn | Node.js, websocketd |
| **Blocking** | No (HTTP/SSE) | No (WebSocket) |
| **Maintenance** | Track SDK versions | Track ACP spec |
| **Flexibility** | Locked to SDK features | Full ACP protocol |

**Trade-off**: Lose SDK-specific features (hooks, custom tools) but gain multi-agent flexibility.

## Success Criteria

- ✅ Connect to Claude Code via websocketd
- ✅ Connect to Gemini CLI via websocketd
- ✅ Non-blocking WebSocket in Shiny
- ✅ Permission handling works (async)
- ✅ Tool execution works (file writes, bash)
- ✅ Streaming responses work
- ✅ Agent switching works
- ✅ At parity with current SDK implementation

## Dependencies

- **External**: Node.js, websocketd (or mcp2websocket), ACP agents
- **Internal**: Current Shiny UI (reusable)
- **Blocking**: None (can prototype immediately)

## Complexity

**Overall**: MEDIUM
- **WebSocket proxy setup**: LOW (websocketd is mature)
- **R WebSocket client**: MEDIUM (websocket package exists)
- **ACP protocol handling**: MEDIUM (JSON-RPC parsing)
- **Multi-agent UI**: LOW (dropdown selector)

## Timeline Estimate

### MVP (At Parity with Current)
- **Phase 1 (Proxy Setup)**: 4-6 hours
- **Phase 2 (R WebSocket Client)**: 8-12 hours
- **Phase 3 (ACP Protocol)**: 8-12 hours
- **Phase 4 (UI Integration)**: 4-6 hours
- **Phase 5 (Testing)**: 6-8 hours
- **Total MVP**: 30-44 hours (~1 week)

### Full Implementation (Multi-Agent + Polish)
- **Phase 6 (Multi-Agent)**: 6-8 hours
- **Phase 7 (Agent Switching)**: 4-6 hours
- **Phase 8 (Polish & Docs)**: 6-8 hours
- **Total Full**: 46-62 hours (~1.5 weeks)

**For AI Agent (Claude)**: Much faster
- Parallel implementation of components
- Automated testing generation
- Likely 2-3 days total for MVP

## Implementation Plan

### Phase 1: WebSocket Proxy Setup (4-6 hours)

#### 1.1 Install websocketd

**Options**:

**Option A: websocketd** (recommended - most mature)
```bash
# macOS
brew install websocketd

# Linux
wget https://github.com/joewalnes/websocketd/releases/download/v0.4.1/websocketd-0.4.1-linux_amd64.zip
unzip websocketd-0.4.1-linux_amd64.zip
sudo mv websocketd /usr/local/bin/
```

**Option B: mcp2websocket** (MCP/ACP specific)
```bash
npm install -g mcp2websocket
```

**Option C: stdio-to-ws** (if we can find it or write our own)
```bash
# Marimo uses this but it's not published
# Could write simple wrapper:
# Node.js script that spawns stdio process and proxies to WebSocket
```

#### 1.2 Test Proxy with Claude

```bash
# Start websocketd wrapping claude-code-acp
websocketd --port=8766 --devconsole npx @zed-industries/claude-code-acp

# Or with mcp2websocket
mcp2websocket --stdio "npx @zed-industries/claude-code-acp" --port 8766
```

**Verify**:
- WebSocket server starts on localhost:8766
- Can connect via browser console
- Send JSON-RPC message, get response

**Files to create**:
- `inst/scripts/start-acp-proxy.sh` - Helper script to start proxy

```bash
#!/bin/bash
# inst/scripts/start-acp-proxy.sh

AGENT=${1:-claude}  # claude or gemini
PORT=${2:-8766}

if [ "$AGENT" = "claude" ]; then
    COMMAND="npx @zed-industries/claude-code-acp"
elif [ "$AGENT" = "gemini" ]; then
    COMMAND="npx @google/gemini-cli --experimental-acp"
else
    echo "Unknown agent: $AGENT"
    exit 1
fi

echo "Starting $AGENT on port $PORT..."
websocketd --port=$PORT "$COMMAND"
```

**Complexity**: LOW
**Timeline**: 2-3 hours
**Parallelizable**: No (foundation)

---

### Phase 2: R WebSocket Client (8-12 hours)

#### 2.1 Install WebSocket Package

```r
# Use websocket package or httpuv
install.packages("websocket")  # Recommended
# OR
install.packages("httpuv")  # Has WebSocket support
```

#### 2.2 Create ACPWebSocketClient

**File**: `R/acp_websocket_client.R`

```r
library(websocket)
library(R6)

ACPWebSocketClient <- R6Class("ACPWebSocketClient",
  public = list(
    initialize = function(ws_url, on_message = NULL, on_error = NULL) {
      private$ws_url <- ws_url
      private$on_message_callback <- on_message
      private$on_error_callback <- on_error
      private$request_id <- 1
      private$pending_requests <- list()
    },

    connect = function() {
      private$ws <- websocket::WebSocket$new(private$ws_url)

      private$ws$onOpen(function(event) {
        message("WebSocket connected")
      })

      private$ws$onMessage(function(event) {
        private$handle_message(event$data)
      })

      private$ws$onError(function(event) {
        if (!is.null(private$on_error_callback)) {
          private$on_error_callback(event$message)
        }
      })

      private$ws$onClose(function(event) {
        message("WebSocket closed")
      })
    },

    send_request = function(method, params = list()) {
      request_id <- private$request_id
      private$request_id <- private$request_id + 1

      request <- list(
        jsonrpc = "2.0",
        id = request_id,
        method = method,
        params = params
      )

      message_json <- jsonlite::toJSON(request, auto_unbox = TRUE)
      private$ws$send(message_json)

      # Return promise-like object
      promise <- promises::promise(function(resolve, reject) {
        private$pending_requests[[as.character(request_id)]] <- list(
          resolve = resolve,
          reject = reject
        )
      })

      promise
    },

    send_notification = function(method, params = list()) {
      notification <- list(
        jsonrpc = "2.0",
        method = method,
        params = params
      )

      message_json <- jsonlite::toJSON(notification, auto_unbox = TRUE)
      private$ws$send(message_json)
    },

    close = function() {
      if (!is.null(private$ws)) {
        private$ws$close()
      }
    }
  ),

  private = list(
    ws_url = NULL,
    ws = NULL,
    request_id = 1,
    pending_requests = list(),
    on_message_callback = NULL,
    on_error_callback = NULL,

    handle_message = function(data) {
      message_obj <- jsonlite::fromJSON(data, simplifyVector = FALSE)

      # Response to request
      if (!is.null(message_obj$id)) {
        request_id <- as.character(message_obj$id)

        if (request_id %in% names(private$pending_requests)) {
          pending <- private$pending_requests[[request_id]]

          if (!is.null(message_obj$error)) {
            pending$reject(message_obj$error)
          } else {
            pending$resolve(message_obj$result)
          }

          private$pending_requests[[request_id]] <- NULL
        }
      }

      # Notification or server-initiated message
      if (!is.null(private$on_message_callback)) {
        private$on_message_callback(message_obj)
      }
    }
  )
)
```

**Complexity**: MEDIUM
**Timeline**: 4-6 hours
**Parallelizable**: No (core component)

---

#### 2.3 ACP Protocol Methods

**File**: `R/acp_methods.R`

```r
acp_initialize <- function(client, client_info) {
  client$send_request("initialize", list(
    protocolVersion = "0.2.0",
    clientInfo = client_info,
    capabilities = list(
      filesystemAccess = TRUE,
      terminalAccess = TRUE
    )
  ))
}

acp_create_session <- function(client) {
  client$send_request("session/new", list())
}

acp_send_prompt <- function(client, session_id, prompt) {
  client$send_request("session/prompt", list(
    sessionId = session_id,
    prompt = list(
      role = "user",
      content = prompt
    )
  ))
}

acp_approve_permission <- function(client, request_id, decision) {
  client$send_notification("session/approve_permission", list(
    requestId = request_id,
    decision = decision  # "allow", "allow_always", "reject"
  ))
}

acp_cancel_session <- function(client, session_id) {
  client$send_notification("session/cancel", list(
    sessionId = session_id
  ))
}
```

**Complexity**: LOW
**Timeline**: 2-3 hours
**Parallelizable**: Yes (after client done)

---

### Phase 3: ACP Protocol Handling (8-12 hours)

#### 3.1 Session Update Handler

**File**: `R/acp_handlers.R`

```r
handle_session_update <- function(update, ui_callbacks) {
  update_type <- update$params$updateType

  if (update_type == "content") {
    # Text content from agent
    content <- update$params$content
    if (!is.null(ui_callbacks$on_text)) {
      ui_callbacks$on_text(content)
    }
  } else if (update_type == "thinking") {
    # Extended thinking
    if (!is.null(ui_callbacks$on_thinking)) {
      ui_callbacks$on_thinking(update$params$thinking)
    }
  } else if (update_type == "toolUse") {
    # Tool being used
    if (!is.null(ui_callbacks$on_tool_use)) {
      ui_callbacks$on_tool_use(
        tool_name = update$params$toolName,
        tool_input = update$params$toolInput
      )
    }
  } else if (update_type == "complete") {
    # Query complete
    if (!is.null(ui_callbacks$on_complete)) {
      ui_callbacks$on_complete()
    }
  } else if (update_type == "error") {
    # Error occurred
    if (!is.null(ui_callbacks$on_error)) {
      ui_callbacks$on_error(update$params$error)
    }
  }
}

handle_permission_request <- function(request, client, auto_approve = TRUE) {
  request_id <- request$params$requestId
  tool_name <- request$params$toolCall$name
  tool_input <- request$params$toolCall$input

  if (auto_approve) {
    # Auto-approve (like current SDK behavior)
    decision <- "allow_always"
  } else {
    # Show UI modal (future feature)
    decision <- show_permission_modal(tool_name, tool_input)
  }

  acp_approve_permission(client, request_id, decision)
}

create_message_router <- function(client, ui_callbacks, auto_approve = TRUE) {
  function(message) {
    method <- message$method

    if (method == "session/update") {
      handle_session_update(message, ui_callbacks)
    } else if (method == "session/request_permission") {
      handle_permission_request(message, client, auto_approve)
    }
  }
}
```

**Complexity**: MEDIUM
**Timeline**: 4-6 hours
**Parallelizable**: Yes (after client done)

---

### Phase 4: UI Integration (4-6 hours)

#### 4.1 Update Shiny Server

**File**: `R/shiny_ui.R` (modifications)

```r
claude_acp_server <- function(input, output, session) {
  # Initialize WebSocket client
  ws_client <- NULL
  acp_session_id <- reactiveVal(NULL)

  # Start websocketd proxy
  proxy_process <- start_websocket_proxy(
    agent = input$agent_type,  # "claude" or "gemini"
    port = 8766
  )

  # Wait for proxy to be ready
  Sys.sleep(2)

  # Connect WebSocket client
  ws_client <<- ACPWebSocketClient$new(
    ws_url = "ws://localhost:8766",
    on_message = create_message_router(
      client = ws_client,
      ui_callbacks = list(
        on_text = function(text) {
          # Update chat UI with streaming text
          current_response <- isolate(response_text())
          response_text(paste0(current_response, text))
        },
        on_tool_use = function(tool_name, tool_input) {
          # Show tool indicator
          tool_status(sprintf("Using tool: %s", tool_name))
        },
        on_complete = function() {
          # Query finished
          is_loading(FALSE)
        },
        on_error = function(error) {
          # Show error
          showNotification(error$message, type = "error")
        }
      ),
      auto_approve = TRUE
    ),
    on_error = function(error) {
      showNotification(paste("WebSocket error:", error), type = "error")
    }
  )

  ws_client$connect()

  # Initialize ACP
  promises::then(
    acp_initialize(ws_client, list(
      name = "RStudio Claude Code",
      version = packageVersion("claudeCodeR")
    )),
    onFulfilled = function(result) {
      # Create session
      promises::then(
        acp_create_session(ws_client),
        onFulfilled = function(session_result) {
          acp_session_id(session_result$sessionId)
          showNotification("Connected to agent", type = "message")
        }
      )
    }
  )

  # Send prompt
  observeEvent(input$send_button, {
    req(input$prompt, acp_session_id())

    is_loading(TRUE)
    response_text("")

    # Send to ACP agent
    acp_send_prompt(
      ws_client,
      session_id = acp_session_id(),
      prompt = build_prompt_with_context(input$prompt)
    )
  })

  # Cleanup on exit
  session$onSessionEnded(function() {
    if (!is.null(ws_client)) {
      ws_client$close()
    }
    if (!is.null(proxy_process)) {
      proxy_process$kill()
    }
  })
}
```

**Complexity**: MEDIUM
**Timeline**: 3-4 hours
**Parallelizable**: Partially (UI separate from backend)

---

#### 4.2 Start Proxy Helper

**File**: `R/proxy_manager.R`

```r
start_websocket_proxy <- function(agent = "claude", port = 8766) {
  # Find websocketd
  websocketd_path <- Sys.which("websocketd")
  if (websocketd_path == "") {
    stop("websocketd not found. Install: brew install websocketd")
  }

  # Determine agent command
  if (agent == "claude") {
    agent_cmd <- "npx @zed-industries/claude-code-acp"
  } else if (agent == "gemini") {
    agent_cmd <- "npx @google/gemini-cli --experimental-acp"
  } else {
    stop("Unknown agent: ", agent)
  }

  # Start proxy process
  proc <- processx::process$new(
    websocketd_path,
    args = c(
      "--port", as.character(port),
      agent_cmd
    ),
    stdout = "|",
    stderr = "|",
    cleanup = TRUE
  )

  # Wait for startup
  Sys.sleep(1)

  if (!proc$is_alive()) {
    stderr <- proc$read_error()
    stop("Failed to start websocketd: ", stderr)
  }

  proc
}

check_websocket_ready <- function(port = 8766, timeout = 10) {
  start_time <- Sys.time()

  while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < timeout) {
    tryCatch({
      # Try to connect
      ws <- websocket::WebSocket$new(sprintf("ws://localhost:%d", port))
      ws$close()
      return(TRUE)
    }, error = function(e) {
      Sys.sleep(0.5)
    })
  }

  FALSE
}
```

**Complexity**: LOW
**Timeline**: 1-2 hours
**Parallelizable**: Yes

---

### Phase 5: Testing (6-8 hours)

#### 5.1 Unit Tests

**File**: `tests/testthat/test-acp-websocket.R`

```r
test_that("ACPWebSocketClient connects", {
  # Mock WebSocket server
  # Test connection
  # Verify onOpen called
})

test_that("send_request works", {
  # Mock server
  # Send request
  # Verify JSON-RPC format
})

test_that("handle_message parses responses", {
  # Mock message
  # Verify parsing
  # Verify callbacks triggered
})

test_that("permission handling works", {
  # Mock permission request
  # Verify auto-approve sends correct response
})
```

#### 5.2 Integration Tests

**Manual testing checklist**:
- [ ] Start Claude via websocketd
- [ ] Connect from R
- [ ] Initialize ACP
- [ ] Create session
- [ ] Send prompt
- [ ] Verify streaming works
- [ ] Verify tool execution works
- [ ] Verify no blocking
- [ ] Switch to Gemini
- [ ] Verify works with different agent

**Complexity**: MEDIUM
**Timeline**: 4-6 hours
**Parallelizable**: Partially

---

### Phase 6: Multi-Agent Support (6-8 hours)

#### 6.1 Agent Configuration

**File**: `R/agent_config.R`

```r
AGENT_CONFIGS <- list(
  claude = list(
    name = "Claude Code",
    command = "npx @zed-industries/claude-code-acp",
    port = 8766,
    icon = "🤖"
  ),
  gemini = list(
    name = "Gemini CLI",
    command = "npx @google/gemini-cli --experimental-acp",
    port = 8767,
    icon = "✨"
  ),
  github = list(
    name = "GitHub Copilot",
    command = "github-copilot-cli",
    port = 8768,
    icon = "🐙"
  )
)

get_agent_config <- function(agent_id) {
  AGENT_CONFIGS[[agent_id]]
}

list_available_agents <- function() {
  # Check which agents are installed
  available <- list()

  for (agent_id in names(AGENT_CONFIGS)) {
    config <- AGENT_CONFIGS[[agent_id]]

    # Check if command exists
    if (check_agent_installed(config$command)) {
      available[[agent_id]] <- config
    }
  }

  available
}

check_agent_installed <- function(command) {
  # Try to run command --version or similar
  result <- system2("which", command, stdout = FALSE, stderr = FALSE)
  result == 0
}
```

#### 6.2 Agent Switcher UI

**File**: `R/shiny_ui.R` (additions)

```r
# In UI
selectInput("agent_type", "Agent:",
            choices = get_agent_choices(),
            selected = "claude")

actionButton("switch_agent", "Switch Agent")

# Get choices from available agents
get_agent_choices <- function() {
  agents <- list_available_agents()
  choices <- sapply(agents, function(a) a$name)
  names(choices) <- names(agents)
  choices
}

# In server
observeEvent(input$switch_agent, {
  # Close current WebSocket
  if (!is.null(ws_client)) {
    ws_client$close()
  }

  # Kill current proxy
  if (!is.null(proxy_process)) {
    proxy_process$kill()
  }

  # Start new proxy for selected agent
  config <- get_agent_config(input$agent_type)
  proxy_process <<- start_websocket_proxy(
    agent = input$agent_type,
    port = config$port
  )

  # Reconnect
  ws_client <<- create_acp_client(config$port)
  ws_client$connect()

  # Re-initialize
  initialize_acp_session()
})
```

**Complexity**: LOW
**Timeline**: 2-3 hours
**Parallelizable**: Yes

---

### Phase 7: Polish & Documentation (6-8 hours)

#### 7.1 Error Handling

- Connection failures
- Agent not installed
- Proxy startup failures
- WebSocket disconnections
- ACP protocol errors

#### 7.2 Documentation

**Update README.md**:
- ACP architecture diagram
- Multi-agent support section
- Installation for each agent
- Comparison with SDK approach

**Create AGENTS.md**:
- List of supported agents
- How to add custom agents
- Agent configuration format

**Complexity**: LOW
**Timeline**: 3-4 hours
**Parallelizable**: Yes

---

## Does This Mean No Python SDK?

**YES!** The ACP+WebSocket approach **completely replaces** the Python SDK server:

### What Goes Away
- ❌ Python FastAPI server (~300 lines)
- ❌ SDK version tracking
- ❌ Python dependency management
- ❌ HTTP/SSE client in R (~150 lines)

### What Replaces It
- ✅ websocketd process (external binary, ~10MB)
- ✅ WebSocket client in R (~200 lines)
- ✅ ACP protocol handling (~150 lines)

### Net Result
- **Less code**: ~350 lines vs ~450 lines (20% reduction)
- **Fewer dependencies**: No Python, just Node.js + websocketd
- **More flexibility**: Any ACP agent, not just Claude
- **Simpler**: WebSocket is simpler than FastAPI + SSE

## MVP Difficulty Assessment (For AI Agent)

### Complexity: MEDIUM-LOW

**Why it's easier than it looks**:

1. **WebSocket package exists**: `websocket` in R works well
2. **websocketd is mature**: Battle-tested, just spawns it
3. **ACP spec is clear**: JSON-RPC 2.0, well-documented
4. **Marimo proves it works**: We have a working example
5. **Can reuse Shiny UI**: Just swap backend

**Challenges**:
1. WebSocket event handling in Shiny (solvable - see marimo)
2. JSON-RPC parsing (straightforward)
3. Testing without real agents (can mock)

### Timeline for AI Agent (Claude)

**Day 1** (8 hours):
- Set up websocketd
- Create ACPWebSocketClient
- Basic JSON-RPC working
- Test with Claude agent

**Day 2** (8 hours):
- ACP protocol methods
- Session update handlers
- Permission handling
- UI integration

**Day 3** (6 hours):
- Multi-agent support
- Testing
- Documentation
- Polish

**Total: 2.5 days for complete implementation**

### For Human Developer

**Week 1**: Core functionality (WebSocket, ACP protocol)
**Week 2**: Multi-agent, testing, polish

**Total: 1.5-2 weeks**

## Recommendation

### When to Choose ACP+WebSocket

**Choose this if**:
- Multi-agent support is important
- Want simpler architecture (no Python server)
- Want to be part of ACP ecosystem
- Okay with beta-level protocol stability

### When to Choose SDK

**Choose this if**:
- Only need Claude
- Want SDK-specific features (hooks, custom tools)
- Want Anthropic's official support
- Need maximum stability

### Hybrid Approach?

**Could do both**:
- Default to SDK (more stable)
- ACP as optional feature flag
- User chooses at runtime

```r
claude_code_addin <- function(use_acp = FALSE) {
  if (use_acp) {
    start_acp_mode()
  } else {
    start_sdk_mode()
  }
}
```

## Next Steps

1. **Prototype** (2-3 days): Implement MVP, compare to SDK
2. **Evaluate**: Which is better for R users?
3. **Decide**: Ship one or both?
4. **Document**: Clear guidance on which to use

## Success Metrics

- [ ] Claude Code works via ACP+WebSocket
- [ ] Gemini CLI works via ACP+WebSocket
- [ ] No console blocking
- [ ] Performance comparable to SDK
- [ ] Code simpler than SDK approach
- [ ] Users can switch agents easily
