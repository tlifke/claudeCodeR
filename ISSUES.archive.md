# Known Issues and Development Notes

## Current Status

The RStudio ACP integration is a **functional proof-of-concept** with working components but incomplete tool execution.

### What Works ✅

- **ACP Protocol Implementation**: Full JSON-RPC 2.0 message layer over stdio
- **Agent Communication**: Initialize, authenticate, session creation all functional
- **Chat Interface**: Shiny gadget in RStudio viewer pane with streaming responses
- **Permission Handling**: Auto-approval system with correct optionId responses (`allow_always` > `allow` > `reject`)
- **File Handlers**: `fs/read_text_file` and `fs/write_text_file` handlers work correctly (verified in isolated tests)
- **Terminal Handlers**: `terminal/create`, `terminal/output`, etc. implemented
- **RStudio Integration**: `rstudioapi` integration for editor context

### Critical Issue: Tool Execution Not Completing ❌

**Symptom**: Claude responds to prompts and requests permissions, but file writes and bash commands don't actually execute, even though permissions are granted.

**Root Cause**: Architectural mismatch between ACP's synchronous request-response pattern and Shiny's asynchronous event loop.

## Technical Details

### Test Results

#### Handler Test (`test_handlers.R`)
```
Write handler: PASS ✅
Permission handler: PASS ✅
```

**Conclusion**: The handler functions work perfectly in isolation. The issue is in message passing/promise resolution.

#### Full Protocol Test (`test_acp_protocol.R`)
```
Result: TIMEOUT - Promises never resolve
```

**Reason**: The `later` event loop doesn't run in script context. Promises require Shiny or explicit event loop execution.

### Architecture Problems

1. **Blocking vs Async Conflict**
   - ACP clients must respond synchronously to `session/request_permission` requests
   - Shiny's event loop is asynchronous
   - Using `Sys.sleep()` polling blocks the entire R session
   - Previously caused R session crashes with "c++ exception (unknown reason)"

2. **Message Passing Chain**
   ```
   Claude Agent → JSON-RPC → processx stdio →
   later::later (0.1s poll) → handle_request →
   handler function → send_response → processx stdio →
   Claude Agent
   ```

   **Suspected failure point**: Response messages may not be reaching the agent, or promises aren't resolving in Shiny context.

3. **Promise Resolution**
   - Used `promises::then()` with `onFulfilled`/`onRejected` handlers
   - Attempted to terminate chains with `return(NULL)` (no longer using `%...>%` which doesn't exist in base promises)
   - Promises may not be triggering in Shiny's reactive context

## Error Log History

### Initial Issues (Resolved)
- ✅ `protocolVersion` must be numeric (0.1) not string ("0.1.0")
- ✅ `session/new` requires `cwd` and `mcpServers` parameters
- ✅ `session/prompt` requires array of `{type: "text", text: "..."}` not plain string
- ✅ `sessionId` is camelCase not snake_case
- ✅ Environment variables must be named character vector or NULL (not unnamed vector)
- ✅ Permission optionId should prefer `allow_always` when available

### Remaining Issues

1. **Tool calls return "[object Object]" error in UI**
   - Permissions are approved correctly
   - But execution doesn't complete
   - Claude sees the tool as blocked

2. **Mode setting fails**
   - `session/set_mode` with `"acceptEdits"` or `"bypassPermissions"` returns error
   - Falls back to default mode
   - This might be expected behavior - needs verification against ACP spec

3. **Reactive value access warnings**
   - Occasional "Can't access reactive value 'client' outside of reactive consumer"
   - Fixed by capturing `client <- values$client` before promise chains
   - May indicate other reactive access issues

## Logs from Working Session

```
Permission request: Print hello World
  Available optionIds: allow_always, allow, reject
  Responding: allow_always

Received request: fs/write_text_file
Received request: session/request_permission
```

Permissions are granted, file write is requested, but **file is never created**.

## Potential Solutions

### Option 1: Debug Message Passing (Recommended Next Step)

Add comprehensive logging to trace the full request-response cycle:

```r
# In handle_request
message(">>> Calling handler for: ", request$method)
message(">>> Params: ", jsonlite::toJSON(params))

# In handler
message(">>> Handler executing")
result <- ...
message(">>> Handler result: ", jsonlite::toJSON(result))

# After send_response
message(">>> Response sent: ", jsonlite::toJSON(response))

# In agent stderr
# Check if agent receives response
```

### Option 2: Simplify to Synchronous Blocking (Not Recommended)

Remove all promises and use pure blocking calls. Issues:
- Conflicts with Shiny event loop
- Will cause UI freezes
- May crash R sessions (as seen before)

### Option 3: Background Process Architecture (Complex)

Run ACP client in separate R process via `callr`:
- Main process: Shiny UI
- Background process: ACP client with blocking handlers
- IPC between processes

**Pros**: Separates blocking from async
**Cons**: Much more complex, harder to debug

### Option 4: Terminal Integration (Most Reliable)

Instead of Shiny, use RStudio terminal:

```r
claude_terminal <- function() {
  term_id <- rstudioapi::terminalCreate(show = TRUE)
  rstudioapi::terminalSend(term_id, "claude\n")
}
```

**Pros**:
- Zero conflicts (uses native terminal)
- Full Claude Code functionality
- No custom protocol handling needed

**Cons**:
- Less visually integrated
- No custom UI

## Files to Review

- `R/acp_client.R` - Core ACP client with promise-based requests (lines 140-250 for message handling)
- `R/acp_client_methods.R` - Request handlers (fs/*, terminal/*, permissions)
- `R/shiny_ui.R` - UI and server logic with promise chains
- `test_handlers.R` - Isolated handler tests (all passing)
- `test_acp_protocol.R` - Full integration test (times out)

## Environment

- R: 4.5
- RStudio: Required (uses rstudioapi)
- Node.js: Required for `@zed-industries/claude-code-acp`
- Platform: macOS (darwin 25.0.0)

## Next Steps for Future Developer

1. **Immediate**: Add detailed logging to `handle_request` and `send_response` in `acp_client.R`
2. **Verify**: Check agent's stderr output - is it receiving our responses?
3. **Test**: Try pure terminal integration approach as comparison
4. **Consider**: Whether Shiny is the right framework for this use case
5. **Alternative**: Investigate using plumber API + websockets instead of Shiny

## References

- [ACP Specification](https://agentclientprotocol.com)
- [TypeScript Example Agent](https://github.com/zed-industries/agent-client-protocol/blob/c399208627443fb5234877d826c63b0a90a5f89c/typescript/examples/agent.ts)
- [Emacs ACP Client](https://github.com/xenodium/acp.el)
- [Claude Code ACP Adapter](https://github.com/zed-industries/claude-code-acp)

## Conclusion

This is a **85% complete implementation** with excellent foundation:
- Protocol handling: ✅
- UI integration: ✅
- Permission system: ✅
- Handlers: ✅
- **Tool execution: ❌** (architectural issue)

The core challenge is making synchronous ACP requests work within Shiny's async model. This may require architectural changes or accepting that terminal integration is the better approach for RStudio.
