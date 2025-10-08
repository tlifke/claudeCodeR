#!/usr/bin/env python3
import os
import sys
import asyncio
import json
from pathlib import Path
from typing import Optional, Dict, Any, List
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse
import uvicorn

try:
    from claude_agent_sdk import ClaudeSDKClient
    from claude_agent_sdk.types import (
        ClaudeAgentOptions,
        PermissionResultAllow,
        PermissionResultDeny,
    )
    from claude_agent_sdk import (
        ClaudeSDKError,
        CLINotFoundError,
        CLIConnectionError,
        ProcessError,
        CLIJSONDecodeError,
    )
except ImportError as e:
    print(
        f"ERROR: claude-agent-sdk not installed or incomplete. Run: pip install claude-agent-sdk\nDetails: {e}",
        file=sys.stderr,
    )
    sys.exit(1)


class SessionState:
    def __init__(self):
        self.working_dir: Optional[str] = None
        self.auth_method: Optional[str] = None
        self.session_active: bool = False
        self.permission_mode: Optional[str] = None
        self.pending_permissions: Dict[str, asyncio.Future] = {}
        self.permission_queue: Optional[asyncio.Queue] = None
        self.allowed_tools: Optional[List[str]] = None
        self.disallowed_tools: Optional[List[str]] = None
        self.model: Optional[str] = None
        self.system_prompt: Optional[str] = None
        self.max_turns: Optional[int] = None
        self.env: Optional[Dict[str, str]] = None
        self.add_dirs: Optional[List[str]] = None
        self.session_id: Optional[str] = None
        self.sdk_client: Optional[ClaudeSDKClient] = None


session_state = SessionState()


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("Claude RStudio SDK Server starting...", file=sys.stderr)
    yield
    print("Claude RStudio SDK Server shutting down...", file=sys.stderr)


app = FastAPI(title="Claude RStudio SDK Server", lifespan=lifespan)


class InitializeRequest(BaseModel):
    working_dir: str
    auth_method: str
    api_key: Optional[str] = None
    aws_region: Optional[str] = None
    aws_profile: Optional[str] = None
    permission_mode: str = "acceptEdits"
    allowed_tools: Optional[List[str]] = None
    disallowed_tools: Optional[List[str]] = None
    model: Optional[str] = None
    system_prompt: Optional[str] = None
    max_turns: Optional[int] = None
    env: Optional[Dict[str, str]] = None
    add_dirs: Optional[List[str]] = None


class QueryRequest(BaseModel):
    prompt: str
    context: Optional[Dict[str, Any]] = None


class ApproveRequest(BaseModel):
    request_id: str
    approved: bool


@app.post("/initialize")
async def initialize(req: InitializeRequest):
    try:
        session_state.working_dir = req.working_dir
        session_state.auth_method = req.auth_method
        session_state.permission_mode = req.permission_mode
        session_state.allowed_tools = req.allowed_tools
        session_state.disallowed_tools = req.disallowed_tools
        session_state.system_prompt = req.system_prompt
        session_state.max_turns = req.max_turns
        session_state.add_dirs = req.add_dirs

        env_vars = {}
        if req.auth_method == "api_key" and req.api_key:
            env_vars["ANTHROPIC_API_KEY"] = req.api_key
            print(f"Using API key authentication", file=sys.stderr)
        elif req.auth_method == "bedrock":
            env_vars["CLAUDE_CODE_USE_BEDROCK"] = "1"
            if req.aws_region:
                env_vars["AWS_REGION"] = req.aws_region
            if req.aws_profile:
                env_vars["AWS_PROFILE"] = req.aws_profile
            print(f"Using AWS Bedrock authentication", file=sys.stderr)
        elif req.auth_method == "subscription":
            print(f"Using Claude subscription (stored credentials)", file=sys.stderr)

        if req.env:
            env_vars.update(req.env)

        session_state.env = env_vars

        for key, value in env_vars.items():
            os.environ[key] = value

        session_state.model = req.model or os.environ.get(
            "ANTHROPIC_MODEL", "claude-sonnet-4-5-20250929"
        )

        os.chdir(session_state.working_dir)

        def stderr_callback(message: str):
            print(f"[SDK STDERR] {message}", file=sys.stderr)

        options_dict = {
            "permission_mode": "default",
            "can_use_tool": can_use_tool_handler,
            "stderr": stderr_callback,
            "extra_args": {"debug-to-stderr": None}
        }
        print(f"[INIT] Set permission_mode='default' to enable can_use_tool callback", file=sys.stderr)
        print(f"[INIT] R client requested permission_mode: {session_state.permission_mode}", file=sys.stderr)

        if session_state.model:
            options_dict["model"] = session_state.model

        if session_state.allowed_tools:
            options_dict["allowed_tools"] = session_state.allowed_tools

        if session_state.disallowed_tools:
            options_dict["disallowed_tools"] = session_state.disallowed_tools

        if session_state.system_prompt:
            options_dict["system_prompt"] = session_state.system_prompt

        if session_state.max_turns:
            options_dict["max_turns"] = session_state.max_turns

        if session_state.add_dirs:
            options_dict["add_dirs"] = session_state.add_dirs

        print(f"[INIT] Creating ClaudeAgentOptions with: {options_dict.keys()}", file=sys.stderr)
        print(f"[INIT] can_use_tool callback is: {options_dict.get('can_use_tool')}", file=sys.stderr)
        print(f"[INIT] permission_mode is: {options_dict.get('permission_mode')}", file=sys.stderr)

        options = ClaudeAgentOptions(**options_dict)
        print(f"[INIT] ClaudeAgentOptions created", file=sys.stderr)
        print(f"[INIT] Options object: {options}", file=sys.stderr)

        session_state.sdk_client = ClaudeSDKClient(options)
        print(f"[INIT] ClaudeSDKClient created", file=sys.stderr)
        print(f"[INIT] Calling sdk_client.connect()...", file=sys.stderr)
        await session_state.sdk_client.connect()
        print(f"[INIT] SDK client created and connected successfully!", file=sys.stderr)

        session_state.session_active = True

        return {
            "status": "ok",
            "working_dir": session_state.working_dir,
            "auth_method": session_state.auth_method,
            "permission_mode": req.permission_mode,
            "model": session_state.model,
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


async def can_use_tool_handler(
    tool_name: str, input_data: Dict[str, Any], context
) -> PermissionResultAllow | PermissionResultDeny:
    print(f"[PERMISSION] can_use_tool_handler CALLED for tool: {tool_name}", file=sys.stderr)
    print(f"[PERMISSION] Input data: {input_data}", file=sys.stderr)
    print(f"[PERMISSION] Permission mode: {session_state.permission_mode}", file=sys.stderr)

    if not session_state.permission_queue:
        print(f"[PERMISSION] No permission queue (not in query mode) - auto-approving", file=sys.stderr)
        return PermissionResultAllow()

    request_id = f"perm_{int(asyncio.get_event_loop().time() * 1000)}_{tool_name}"
    future = asyncio.Future()
    session_state.pending_permissions[request_id] = future

    print(f"[PERMISSION] Created request: {request_id}", file=sys.stderr)
    print(f"[PERMISSION] Adding to permission queue", file=sys.stderr)
    await session_state.permission_queue.put(
        {"request_id": request_id, "tool_name": tool_name, "input": input_data}
    )
    print(f"[PERMISSION] Added to queue successfully", file=sys.stderr)

    print(f"[PERMISSION] Waiting for approval (60s timeout)...", file=sys.stderr)

    try:
        result = await asyncio.wait_for(future, timeout=60.0)
    except asyncio.TimeoutError:
        print(f"[PERMISSION] TIMEOUT after 60s, auto-denying: {request_id}", file=sys.stderr)
        result = False

    if request_id in session_state.pending_permissions:
        del session_state.pending_permissions[request_id]
    print(f"[PERMISSION] Resolved: {request_id} -> {result}", file=sys.stderr)

    if result:
        print(f"[PERMISSION] Returning PermissionResultAllow with updated_input", file=sys.stderr)
        return PermissionResultAllow(updated_input=input_data)
    else:
        print(f"[PERMISSION] Returning PermissionResultDeny", file=sys.stderr)
        return PermissionResultDeny(message="User denied permission")


@app.post("/approve")
async def approve_permission(req: ApproveRequest):
    if req.request_id not in session_state.pending_permissions:
        raise HTTPException(status_code=404, detail="Permission request not found")

    future = session_state.pending_permissions[req.request_id]
    future.set_result(req.approved)

    return {"status": "ok"}


@app.post("/query")
async def query_agent(req: QueryRequest):
    if not session_state.session_active:
        raise HTTPException(
            status_code=400, detail="Session not initialized. Call /initialize first."
        )

    async def event_generator():
        session_state.permission_queue = asyncio.Queue()
        event_queue = asyncio.Queue()
        query_done = asyncio.Event()

        async def permission_monitor():
            while not query_done.is_set():
                try:
                    perm_req = await asyncio.wait_for(
                        session_state.permission_queue.get(), timeout=0.1
                    )
                    await event_queue.put(
                        {"event": "permission_request", "data": json.dumps(perm_req)}
                    )
                except asyncio.TimeoutError:
                    continue

        async def run_query():
            try:
                full_prompt = req.prompt

                if req.context:
                    context_parts = []
                    if req.context.get("path"):
                        context_parts.append(f"Current file: {req.context['path']}")
                    if req.context.get("selection") and req.context["selection"].get(
                        "text"
                    ):
                        context_parts.append(
                            f"Selected code:\n```\n{req.context['selection']['text']}\n```"
                        )
                    elif req.context.get("content"):
                        context_parts.append(
                            f"File content:\n```\n{req.context['content']}\n```"
                        )

                    if context_parts:
                        full_prompt = "\n\n".join(context_parts) + "\n\n" + req.prompt

                print(f"Querying with prompt: {full_prompt[:100]}...", file=sys.stderr)

                if not session_state.sdk_client:
                    raise Exception("SDK client not initialized. Call /initialize first.")

                await session_state.sdk_client.query(full_prompt)

                async for message in session_state.sdk_client.receive_response():
                        msg_type = type(message).__name__
                        print(f"Got message: {msg_type}", file=sys.stderr)

                        if msg_type == "ResultMessage":
                            session_id = getattr(message, "session_id", None)
                            if session_id:
                                session_state.session_id = session_id
                                print(
                                    f"Captured session_id: {session_id}",
                                    file=sys.stderr,
                                )

                            result_data = {
                                "duration_ms": getattr(message, "duration_ms", None),
                                "duration_api_ms": getattr(
                                    message, "duration_api_ms", None
                                ),
                                "is_error": getattr(message, "is_error", False),
                                "num_turns": getattr(message, "num_turns", None),
                                "session_id": session_id,
                                "total_cost_usd": getattr(
                                    message, "total_cost_usd", None
                                ),
                            }
                            if hasattr(message, "usage"):
                                result_data["usage"] = {
                                    "input_tokens": getattr(
                                        message.usage, "input_tokens", 0
                                    ),
                                    "output_tokens": getattr(
                                        message.usage, "output_tokens", 0
                                    ),
                                    "cache_creation_input_tokens": getattr(
                                        message.usage, "cache_creation_input_tokens", 0
                                    ),
                                    "cache_read_input_tokens": getattr(
                                        message.usage, "cache_read_input_tokens", 0
                                    ),
                                }
                            await event_queue.put(
                                {"event": "result", "data": json.dumps(result_data)}
                            )
                            print(
                                f"Emitted ResultMessage: cost=${result_data.get('total_cost_usd', 0):.4f}",
                                file=sys.stderr,
                            )

                        if hasattr(message, "content"):
                            for block in message.content:
                                block_type = type(block).__name__

                                if block_type == "ThinkingBlock":
                                    thinking_data = {
                                        "thinking": getattr(block, "thinking", ""),
                                        "signature": getattr(block, "signature", None),
                                    }
                                    await event_queue.put(
                                        {
                                            "event": "thinking",
                                            "data": json.dumps(thinking_data),
                                        }
                                    )
                                    print(
                                        f"Emitted ThinkingBlock: {len(thinking_data['thinking'])} chars",
                                        file=sys.stderr,
                                    )

                                elif block_type == "ToolUseBlock":
                                    tool_use_data = {
                                        "id": getattr(block, "id", None),
                                        "name": getattr(block, "name", ""),
                                        "input": getattr(block, "input", {}),
                                    }
                                    await event_queue.put(
                                        {
                                            "event": "tool_use",
                                            "data": json.dumps(tool_use_data),
                                        }
                                    )
                                    print(
                                        f"Emitted ToolUseBlock: {tool_use_data['name']}",
                                        file=sys.stderr,
                                    )

                                elif hasattr(block, "text"):
                                    await event_queue.put(
                                        {
                                            "event": "text",
                                            "data": json.dumps({"text": block.text}),
                                        }
                                    )
                                    print(
                                        f"Emitted TextBlock: {len(block.text)} chars",
                                        file=sys.stderr,
                                    )

                                elif block_type == "ToolResultBlock" and hasattr(
                                    block, "content"
                                ):
                                    if isinstance(block.content, str):
                                        await event_queue.put(
                                            {
                                                "event": "tool_result",
                                                "data": json.dumps(
                                                    {"content": block.content}
                                                ),
                                            }
                                        )
                                        print(
                                            f"Emitted ToolResult: {len(block.content)} chars",
                                            file=sys.stderr,
                                        )

                print(f"[QUERY] Query completed, emitting complete event", file=sys.stderr)
                await event_queue.put(
                    {"event": "complete", "data": json.dumps({"status": "complete"})}
                )
                print(f"[QUERY] Complete event added to queue", file=sys.stderr)

            except CLINotFoundError as e:
                print(f"CLI not found error: {str(e)}", file=sys.stderr)
                await event_queue.put(
                    {
                        "event": "error",
                        "data": json.dumps(
                            {
                                "error": str(e),
                                "error_type": "cli_not_found",
                                "message": "Claude CLI not found. Install: npm install -g @anthropic-ai/claude-code",
                            }
                        ),
                    }
                )
            except CLIConnectionError as e:
                print(f"CLI connection error: {str(e)}", file=sys.stderr)
                await event_queue.put(
                    {
                        "event": "error",
                        "data": json.dumps(
                            {
                                "error": str(e),
                                "error_type": "connection_error",
                                "message": f"Connection to Claude failed: {str(e)}",
                            }
                        ),
                    }
                )
            except ProcessError as e:
                print(f"Process error: {str(e)}", file=sys.stderr)
                exit_code = getattr(e, "exit_code", None)
                await event_queue.put(
                    {
                        "event": "error",
                        "data": json.dumps(
                            {
                                "error": str(e),
                                "error_type": "process_error",
                                "exit_code": exit_code,
                                "message": f"Claude process error (exit code {exit_code}): {str(e)}",
                            }
                        ),
                    }
                )
            except CLIJSONDecodeError as e:
                print(f"JSON decode error: {str(e)}", file=sys.stderr)
                await event_queue.put(
                    {
                        "event": "error",
                        "data": json.dumps(
                            {
                                "error": str(e),
                                "error_type": "json_decode_error",
                                "message": f"Failed to parse Claude response: {str(e)}",
                            }
                        ),
                    }
                )
            except ClaudeSDKError as e:
                print(f"SDK error: {str(e)}", file=sys.stderr)
                await event_queue.put(
                    {
                        "event": "error",
                        "data": json.dumps(
                            {
                                "error": str(e),
                                "error_type": "sdk_error",
                                "message": str(e),
                            }
                        ),
                    }
                )
            except Exception as e:
                print(f"Query error: {str(e)}", file=sys.stderr)
                import traceback

                traceback.print_exc(file=sys.stderr)
                await event_queue.put(
                    {
                        "event": "error",
                        "data": json.dumps(
                            {
                                "error": str(e),
                                "error_type": "unknown",
                                "message": str(e),
                            }
                        ),
                    }
                )
            finally:
                query_done.set()

        monitor_task = asyncio.create_task(permission_monitor())
        query_task = asyncio.create_task(run_query())

        while not query_done.is_set() or not event_queue.empty():
            try:
                event = await asyncio.wait_for(event_queue.get(), timeout=0.1)
                yield event
            except asyncio.TimeoutError:
                continue

        await query_task
        monitor_task.cancel()
        session_state.permission_queue = None

    return EventSourceResponse(event_generator())


@app.post("/shutdown")
async def shutdown():
    if session_state.sdk_client:
        try:
            await session_state.sdk_client.disconnect()
            print("SDK client disconnected", file=sys.stderr)
        except Exception as e:
            print(f"Error disconnecting SDK client: {e}", file=sys.stderr)
        session_state.sdk_client = None

    session_state.session_active = False
    session_state.working_dir = None
    session_state.auth_method = None
    session_state.permission_mode = None
    session_state.allowed_tools = None
    session_state.disallowed_tools = None
    session_state.model = None
    session_state.system_prompt = None
    session_state.max_turns = None
    session_state.env = None
    session_state.add_dirs = None
    session_state.session_id = None
    return {"status": "ok"}


@app.get("/health")
async def health():
    return {
        "status": "ok" if session_state.session_active else "not_initialized",
        "working_dir": session_state.working_dir,
        "auth_method": session_state.auth_method,
    }


def main():
    port = int(os.environ.get("PORT", 8765))
    host = os.environ.get("HOST", "127.0.0.1")

    uvicorn.run(app, host=host, port=port, log_level="info", access_log=False)


if __name__ == "__main__":
    main()
