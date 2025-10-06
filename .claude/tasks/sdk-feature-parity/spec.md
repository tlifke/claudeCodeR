# Task: Claude Agent SDK Feature Parity

## Goal

Implement full feature parity with the Claude Agent SDK for Python, expanding from current ~15% coverage to 100% of BASIC and INTERMEDIATE features. This maintains the proven HTTP/SSE architecture while adding missing functionality.

## Success Criteria

- ✅ All BASIC SDK features implemented and tested (12 features)
- ✅ All INTERMEDIATE SDK features implemented and tested (14 features)
- ✅ Python tests passing (unit + integration)
- ✅ R tests passing (calling MCP server)
- ✅ No regressions in existing functionality
- ✅ Documentation updated with new features

## Dependencies

- **External**: Python 3.10+, Claude Agent SDK
- **Internal**: Current v0.2.0 codebase (working baseline)
- **Blocking**: None (can start immediately)

## Complexity

**Overall**: HIGH
- **BASIC features**: MEDIUM (straightforward but many)
- **INTERMEDIATE features**: HIGH (session persistence, streaming)
- **Testing**: MEDIUM (infrastructure exists)

## Timeline Estimate

- **Phase 1 (BASIC)**: 3-4 weeks (parallelizable)
- **Phase 2 (INTERMEDIATE)**: 4-5 weeks (some sequential)
- **Phase 3 (Testing & Polish)**: 1-2 weeks
- **Total**: 8-11 weeks

## Parallelization Strategy

### Git Worktree Approach

Use git worktrees to develop features in parallel:

```bash
# Main branch
git worktree add ../claudeCodeR-worktree-tools feature/tool-control
git worktree add ../claudeCodeR-worktree-models feature/model-selection
git worktree add ../claudeCodeR-worktree-messages feature/message-types
git worktree add ../claudeCodeR-worktree-errors feature/error-handling
```

### Parallel Tracks (4 developers ideal)

**Developer 1: Configuration Features (Weeks 1-3)**
- Tool control (allowed_tools, disallowed_tools)
- Model selection
- System prompts
- Turn limits

**Developer 2: Session & State (Weeks 1-4)**
- Multi-session support (session_id)
- Session persistence (continue_conversation, resume)
- Connection lifecycle (connect, disconnect, interrupt)

**Developer 3: Messages & Errors (Weeks 1-3)**
- SDK error types
- ResultMessage with cost/usage tracking
- ThinkingBlock, ToolUseBlock
- Message type parsing

**Developer 4: Settings & Environment (Weeks 1-3)**
- Settings loading (CLAUDE.md)
- Environment configuration
- Additional directories (add_dirs)
- Workspace management

**Integration Week (Week 4-5)**: Merge all branches, resolve conflicts, integration testing

**Repeat for INTERMEDIATE features (Weeks 6-10)**

## Implementation Plan

### Phase 1: BASIC Features (Weeks 1-4)

#### 1.1 Tool Control (Week 1)

**Files to modify**:
- `python/sdk_server.py` - Add to ClaudeAgentOptions
- `R/sdk_client.R` - Add initialization parameters

**Implementation**:
```python
# python/sdk_server.py
class InitializeRequest(BaseModel):
    # ... existing fields ...
    allowed_tools: Optional[List[str]] = None
    disallowed_tools: Optional[List[str]] = None

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    options = ClaudeAgentOptions(
        allowed_tools=req.allowed_tools,
        disallowed_tools=req.disallowed_tools,
        # ... other options ...
    )
```

```r
# R/sdk_client.R
initialize_session <- function(client, working_dir, auth_config,
                               allowed_tools = NULL, disallowed_tools = NULL) {
  body <- list(
    working_dir = working_dir,
    auth_method = auth_config$method,
    allowed_tools = allowed_tools,
    disallowed_tools = disallowed_tools
  )
  # POST to /initialize
}
```

**Tests**:
- Python: Test tool filtering works
- R: Test parameters passed correctly
- Integration: Verify only allowed tools execute

**Complexity**: LOW
**Timeline**: 1 day
**Parallelizable**: Yes

---

#### 1.2 Model Selection (Week 1)

**Files to modify**:
- `python/sdk_server.py`
- `R/config.R` - Add model detection/configuration

**Implementation**:
```python
# python/sdk_server.py
class InitializeRequest(BaseModel):
    model: Optional[str] = None

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    options = ClaudeAgentOptions(
        model=req.model or "claude-sonnet-4-5-20250929",
        # ...
    )
```

**Environment variables**:
- `ANTHROPIC_MODEL` - Primary model
- `ANTHROPIC_SMALL_FAST_MODEL` - Fast model for simple queries

**Tests**:
- Verify model selection from env vars
- Verify explicit model override works

**Complexity**: LOW
**Timeline**: 1 day
**Parallelizable**: Yes

---

#### 1.3 System Prompts (Week 1)

**Files to modify**:
- `python/sdk_server.py`

**Implementation**:
```python
class InitializeRequest(BaseModel):
    system_prompt: Optional[str] = None

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    options = ClaudeAgentOptions(
        system_prompt=req.system_prompt,
        # ...
    )
```

**Features**:
- Custom system prompts
- Preset support (if SDK provides)
- Combine with R-specific context

**Tests**:
- Custom prompt works
- Default prompt works
- R context injection works

**Complexity**: LOW
**Timeline**: 1 day
**Parallelizable**: Yes

---

#### 1.4 Turn Limits (Week 1)

**Files to modify**:
- `python/sdk_server.py`

**Implementation**:
```python
class InitializeRequest(BaseModel):
    max_turns: Optional[int] = None

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    options = ClaudeAgentOptions(
        max_turns=req.max_turns,
        # ...
    )
```

**Error handling**:
- Detect when max_turns reached
- Return clear error to user
- Offer to continue with new session

**Tests**:
- Verify enforcement works
- Verify error message clear

**Complexity**: LOW
**Timeline**: 1 day
**Parallelizable**: Yes

---

#### 1.5 SDK Error Types (Week 2)

**Files to modify**:
- `python/sdk_server.py` - Replace HTTPException
- `R/sdk_client.R` - Parse error types

**Implementation**:
```python
from claude_agent_sdk import (
    ClaudeSDKError,
    CLINotFoundError,
    CLIConnectionError,
    ProcessError,
    CLIJSONDecodeError
)

@app.post("/query")
async def query_agent(req: QueryRequest):
    try:
        # ... SDK query ...
    except CLINotFoundError as e:
        raise HTTPException(
            status_code=503,
            detail={"type": "cli_not_found", "message": str(e)}
        )
    except CLIConnectionError as e:
        raise HTTPException(
            status_code=503,
            detail={"type": "connection_error", "message": str(e)}
        )
    except ProcessError as e:
        raise HTTPException(
            status_code=500,
            detail={"type": "process_error", "exit_code": e.exit_code, "message": str(e)}
        )
```

**R error parsing**:
```r
handle_error_response <- function(response) {
  error_data <- httr::content(response, as = "parsed")

  if (error_data$type == "cli_not_found") {
    stop("Claude CLI not found. Install: npm install -g claude-code")
  } else if (error_data$type == "connection_error") {
    stop("Connection to Claude failed: ", error_data$message)
  } else if (error_data$type == "process_error") {
    stop("Claude process error (exit code ", error_data$exit_code, "): ", error_data$message)
  }
}
```

**Tests**:
- Mock each error type
- Verify R gets correct error
- Verify user-friendly messages

**Complexity**: LOW
**Timeline**: 2 days
**Parallelizable**: Yes

---

#### 1.6 ResultMessage with Cost/Usage (Week 2)

**Files to modify**:
- `python/sdk_server.py` - Capture ResultMessage
- `R/sdk_client.R` - Parse and display

**Implementation**:
```python
@app.post("/query")
async def query_agent(req: QueryRequest):
    async def event_generator():
        async with ClaudeSDKClient(options) as client:
            await client.query(full_prompt)

            async for message in client.receive_response():
                # ... handle TextBlock, ToolResultBlock ...

                # NEW: Handle ResultMessage
                if type(message).__name__ == 'ResultMessage':
                    result_data = {
                        "duration_ms": message.duration_ms,
                        "duration_api_ms": message.duration_api_ms,
                        "is_error": message.is_error,
                        "num_turns": message.num_turns,
                        "session_id": message.session_id,
                        "total_cost_usd": message.total_cost_usd,
                        "usage": {
                            "input_tokens": message.usage.input_tokens,
                            "output_tokens": message.usage.output_tokens,
                            "cache_creation_input_tokens": message.usage.cache_creation_input_tokens,
                            "cache_read_input_tokens": message.usage.cache_read_input_tokens
                        }
                    }
                    await event_queue.put({
                        "event": "result",
                        "data": json.dumps(result_data)
                    })
```

**R display**:
```r
# In Shiny UI, show cost info
output$usage_info <- renderText({
  req(result_message())
  sprintf("Cost: $%.4f | Tokens: %d in, %d out | Time: %.1fs",
          result_message()$total_cost_usd,
          result_message()$usage$input_tokens,
          result_message()$usage$output_tokens,
          result_message()$duration_ms / 1000)
})
```

**Tests**:
- Verify cost calculation accurate
- Verify token counts match
- Verify UI displays correctly

**Complexity**: MEDIUM
**Timeline**: 2 days
**Parallelizable**: Yes

---

#### 1.7 ThinkingBlock Support (Week 2)

**Files to modify**:
- `python/sdk_server.py` - Detect and stream ThinkingBlock

**Implementation**:
```python
async for message in client.receive_response():
    if hasattr(message, 'content'):
        for block in message.content:
            if type(block).__name__ == 'ThinkingBlock':
                await event_queue.put({
                    "event": "thinking",
                    "data": json.dumps({
                        "thinking": block.thinking,
                        "signature": block.signature if hasattr(block, 'signature') else None
                    })
                })
```

**R UI**:
```r
# Show thinking in UI (collapsed by default, expandable)
output$thinking_display <- renderUI({
  req(thinking_content())
  tagList(
    tags$details(
      tags$summary("💭 Extended thinking..."),
      tags$pre(thinking_content())
    )
  )
})
```

**Complexity**: LOW
**Timeline**: 1 day
**Parallelizable**: Yes

---

#### 1.8 ToolUseBlock Visibility (Week 2)

**Files to modify**:
- `python/sdk_server.py`

**Implementation**:
```python
if type(block).__name__ == 'ToolUseBlock':
    await event_queue.put({
        "event": "tool_use",
        "data": json.dumps({
            "id": block.id,
            "name": block.name,
            "input": block.input
        })
    })
```

**R UI**:
```r
# Show tool usage in chat
output$tool_indicator <- renderUI({
  req(tool_use())
  tags$div(
    class = "tool-use",
    sprintf("🔧 Using tool: %s", tool_use()$name)
  )
})
```

**Complexity**: LOW
**Timeline**: 1 day
**Parallelizable**: Yes

---

#### 1.9 Multi-Session Support (Week 3-4)

**Files to modify**:
- `python/sdk_server.py` - Track multiple sessions
- `R/sdk_client.R` - Session ID handling
- `R/shiny_ui.R` - Session switcher UI

**Implementation**:
```python
# Global session store
sessions: Dict[str, ClaudeSDKClient] = {}

class InitializeRequest(BaseModel):
    session_id: Optional[str] = None  # Resume existing or create new

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    session_id = req.session_id or str(uuid.uuid4())

    if session_id in sessions:
        # Resume existing session
        return {"session_id": session_id, "status": "resumed"}

    # Create new session
    client = ClaudeSDKClient(options)
    sessions[session_id] = client

    return {"session_id": session_id, "status": "created"}

class QueryRequest(BaseModel):
    session_id: str
    prompt: str
    context: Optional[Dict[str, Any]] = None

@app.post("/query")
async def query_agent(req: QueryRequest):
    if req.session_id not in sessions:
        raise HTTPException(404, "Session not found")

    client = sessions[req.session_id]
    # ... query with this client ...
```

**R UI additions**:
```r
# Session switcher
selectInput("session_id", "Session:",
            choices = get_session_list(),
            selected = current_session())

actionButton("new_session", "New Session")
actionButton("delete_session", "Delete Session")
```

**Tests**:
- Create multiple sessions
- Switch between sessions
- Verify isolation (no cross-talk)
- Delete sessions cleanly

**Complexity**: HIGH
**Timeline**: 3-4 days
**Parallelizable**: Partially (backend separate from UI)

---

#### 1.10 Permission Mode Support (Week 3)

**Files to modify**:
- `python/sdk_server.py`

**Implementation**:
```python
class InitializeRequest(BaseModel):
    permission_mode: str = "acceptEdits"  # default, plan, bypassPermissions

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    options = ClaudeAgentOptions(
        permission_mode=req.permission_mode,
        # ...
    )
```

**Modes**:
- `default`: Ask for each tool
- `acceptEdits`: Auto-approve file edits (current behavior)
- `plan`: Plan mode (read-only)
- `bypassPermissions`: Auto-approve everything

**UI**:
```r
selectInput("permission_mode", "Permission Mode:",
            choices = c("Auto-approve edits" = "acceptEdits",
                       "Ask every time" = "default",
                       "Plan only" = "plan",
                       "Auto-approve all" = "bypassPermissions"))
```

**Complexity**: LOW
**Timeline**: 1 day
**Parallelizable**: Yes

---

#### 1.11-1.12 Environment & Workspace Config (Week 3)

**Files to modify**:
- `python/sdk_server.py`
- `R/config.R`

**Implementation**:
```python
class InitializeRequest(BaseModel):
    env: Optional[Dict[str, str]] = None
    add_dirs: Optional[List[str]] = None

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    options = ClaudeAgentOptions(
        env=req.env or {},
        add_dirs=req.add_dirs or [],
        # ...
    )
```

**Features**:
- Pass R environment variables to SDK
- Support multi-repo workspaces
- Detect related projects automatically

**Complexity**: LOW
**Timeline**: 1 day
**Parallelizable**: Yes

---

### Phase 2: INTERMEDIATE Features (Weeks 5-10)

#### 2.1 Settings Loading (CLAUDE.md) (Week 5)

**Files to modify**:
- `python/sdk_server.py`

**Implementation**:
```python
class InitializeRequest(BaseModel):
    setting_sources: Optional[List[str]] = ["project", "user"]

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    options = ClaudeAgentOptions(
        setting_sources=req.setting_sources,
        # ...
    )
```

**Features**:
- Load project-level CLAUDE.md
- Load user-level CLAUDE.md (~/.claude/CLAUDE.md)
- Precedence: project > user

**Tests**:
- Verify file loading works
- Verify precedence correct
- Verify missing files handled gracefully

**Complexity**: MEDIUM
**Timeline**: 2-3 days
**Parallelizable**: Yes

---

#### 2.2 Session Persistence (Week 5-6)

**Files to modify**:
- `python/sdk_server.py`
- New: `python/session_store.py`

**Implementation**:
```python
class InitializeRequest(BaseModel):
    continue_conversation: bool = False
    resume: Optional[str] = None  # Session ID to resume

# Session store (could be file-based or DB)
class SessionStore:
    def save_session(self, session_id: str, state: dict):
        # Serialize session state to disk

    def load_session(self, session_id: str) -> dict:
        # Deserialize from disk

    def list_sessions(self) -> List[dict]:
        # Return all saved sessions

@app.post("/initialize")
async def initialize(req: InitializeRequest):
    if req.resume:
        # Load saved session
        state = session_store.load_session(req.resume)
        # Restore SDK client from state

    options = ClaudeAgentOptions(
        continue_conversation=req.continue_conversation,
        # ...
    )
```

**Features**:
- Save conversation history
- Resume from saved session
- List available sessions
- Auto-save on exit

**Tests**:
- Create session, save, exit, resume
- Verify conversation history intact
- Verify context preserved

**Complexity**: HIGH
**Timeline**: 4-5 days
**Parallelizable**: No (core feature)

---

#### 2.3 Connection Lifecycle (Week 6-7)

**Files to modify**:
- `python/sdk_server.py`

**Implementation**:
```python
@app.post("/connect")
async def connect(session_id: str):
    if session_id not in sessions:
        raise HTTPException(404, "Session not found")

    client = sessions[session_id]
    await client.connect()

    return {"status": "connected"}

@app.post("/disconnect")
async def disconnect(session_id: str):
    if session_id not in sessions:
        raise HTTPException(404, "Session not found")

    client = sessions[session_id]
    await client.disconnect()

    return {"status": "disconnected"}

@app.post("/interrupt")
async def interrupt(session_id: str):
    if session_id not in sessions:
        raise HTTPException(404, "Session not found")

    client = sessions[session_id]
    await client.interrupt()

    return {"status": "interrupted"}
```

**Features**:
- Explicit connect/disconnect
- Interrupt ongoing queries
- Proper cleanup on disconnect

**Tests**:
- Connect, query, disconnect
- Interrupt mid-query
- Verify cleanup happens

**Complexity**: MEDIUM
**Timeline**: 2-3 days
**Parallelizable**: Yes

---

#### 2.4 Advanced Streaming (Week 7)

**Files to modify**:
- `python/sdk_server.py`

**Features**:
- Streaming input support
- Partial message support
- `receive_messages()` vs `receive_response()`

**Implementation**:
```python
class QueryRequest(BaseModel):
    streaming_input: bool = False
    include_partial_messages: bool = False

@app.post("/query")
async def query_agent(req: QueryRequest):
    if req.streaming_input:
        # Use streaming input API
        pass

    if req.include_partial_messages:
        # Include partial messages in stream
        pass
```

**Complexity**: MEDIUM
**Timeline**: 2-3 days
**Parallelizable**: Yes

---

#### 2.5-2.8 Additional Configuration (Week 8)

**Files to modify**:
- `python/sdk_server.py`

**Features**:
- `max_buffer_size`
- `debug_stderr`
- `user` identifier
- Additional env config

**Complexity**: LOW
**Timeline**: 2-3 days total
**Parallelizable**: Yes

---

### Phase 3: Testing & Integration (Weeks 9-11)

#### 3.1 Unit Tests (Week 9)

**Python tests** (`python/test_sdk_server.py`):
```python
def test_tool_control():
    # Test allowed_tools filters correctly

def test_model_selection():
    # Test model parameter works

def test_error_handling():
    # Test each error type

def test_session_persistence():
    # Test save/load works
```

**R tests** (`tests/testthat/test-sdk-client.R`):
```r
test_that("initialize_session works", {
  # Mock HTTP server
  # Call initialize_session
  # Verify request correct
})

test_that("query streaming works", {
  # Mock SSE stream
  # Call query
  # Verify parsing correct
})
```

**Complexity**: MEDIUM
**Timeline**: 3-4 days
**Parallelizable**: Yes (Python and R separate)

---

#### 3.2 Integration Tests (Week 10)

**End-to-end tests**:
```python
@pytest.mark.integration
async def test_full_query_flow():
    # Start server
    # Initialize session from R
    # Send query from R
    # Verify response received
    # Verify tools executed
    # Shutdown cleanly
```

**Test scenarios**:
- API key auth
- Bedrock auth
- Multi-session
- Session resume
- Tool filtering
- Error recovery

**Complexity**: MEDIUM
**Timeline**: 3-4 days
**Parallelizable**: Partially

---

#### 3.3 Documentation (Week 11)

**Files to update**:
- `README.md` - New features
- `CLAUDE.md` - SDK feature list
- API documentation for each feature
- Migration guide from v0.2.0 to v0.3.0

**Complexity**: LOW
**Timeline**: 2-3 days
**Parallelizable**: Yes

---

## Testing Requirements

### Unit Tests

**Python** (pytest):
- Configuration parsing
- Error type handling
- Session management
- Message parsing
- Each new feature

**R** (testthat):
- HTTP client
- SSE parsing
- Error handling
- UI components

### Integration Tests

**Python + R**:
- Full query flow
- Multi-session
- Session persistence
- Tool execution
- Permission handling

### Manual Testing Checklist

- [ ] API key authentication
- [ ] Bedrock authentication (SSO)
- [ ] Bedrock authentication (direct)
- [ ] Tool filtering works
- [ ] Model selection works
- [ ] System prompts work
- [ ] Turn limits enforced
- [ ] Cost tracking accurate
- [ ] Sessions isolate correctly
- [ ] Session resume works
- [ ] Interrupt works
- [ ] All error types handled

## Risks & Mitigation

### Risk 1: SDK API Changes
**Probability**: MEDIUM
**Impact**: HIGH
**Mitigation**: Pin SDK version, monitor releases, test before upgrading

### Risk 2: Session State Too Large
**Probability**: LOW
**Impact**: MEDIUM
**Mitigation**: Implement compression, cleanup old sessions, limit history

### Risk 3: Performance Degradation
**Probability**: LOW
**Impact**: MEDIUM
**Mitigation**: Benchmark each feature, optimize hot paths, add caching

### Risk 4: Merge Conflicts
**Probability**: MEDIUM
**Impact**: MEDIUM
**Mitigation**: Frequent integration, clear ownership boundaries, good communication

## Success Verification

### Automated
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] No performance regression
- [ ] Code coverage >80%

### Manual
- [ ] Feature demo with each capability
- [ ] User acceptance testing
- [ ] Documentation reviewed
- [ ] No critical bugs

## Deliverables

1. **Code**: All features implemented
2. **Tests**: Comprehensive test suite
3. **Documentation**: Updated README, API docs, migration guide
4. **Release**: v0.3.0 with full SDK parity

## Next Steps After Completion

1. Evaluate ADVANCED features (hooks, custom tools, MCP)
2. UI improvements (Task: ui-improvements.md)
3. Consider ACP integration (Task: acp-websocket-integration.md)
