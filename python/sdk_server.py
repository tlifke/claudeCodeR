#!/usr/bin/env python3
import os
import sys
import asyncio
import json
from pathlib import Path
from typing import Optional, Dict, Any
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse
import uvicorn

try:
    from claude_agent_sdk import ClaudeSDKClient
    from claude_agent_sdk.types import ClaudeAgentOptions, PermissionResultAllow, PermissionResultDeny
except ImportError:
    print("ERROR: claude-agent-sdk not installed. Run: pip install claude-agent-sdk", file=sys.stderr)
    sys.exit(1)


class SessionState:
    def __init__(self):
        self.working_dir: Optional[str] = None
        self.auth_method: Optional[str] = None
        self.session_active: bool = False
        self.permission_mode: Optional[str] = None
        self.pending_permissions: Dict[str, asyncio.Future] = {}
        self.permission_queue: Optional[asyncio.Queue] = None


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

        for key, value in env_vars.items():
            os.environ[key] = value

        os.chdir(session_state.working_dir)

        session_state.session_active = True
        session_state.permission_mode = req.permission_mode

        return {
            "status": "ok",
            "working_dir": session_state.working_dir,
            "auth_method": session_state.auth_method,
            "permission_mode": req.permission_mode
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


async def can_use_tool_handler(tool_name: str, input_data: Dict[str, Any], context) -> PermissionResultAllow | PermissionResultDeny:
    request_id = f"perm_{int(asyncio.get_event_loop().time() * 1000)}_{tool_name}"
    future = asyncio.Future()
    session_state.pending_permissions[request_id] = future

    print(f"Permission request: {request_id} for tool {tool_name}", file=sys.stderr)

    if session_state.permission_queue:
        await session_state.permission_queue.put({
            "request_id": request_id,
            "tool_name": tool_name,
            "input": input_data
        })

    result = await future

    del session_state.pending_permissions[request_id]
    print(f"Permission resolved: {request_id} -> {result}", file=sys.stderr)

    if result:
        return PermissionResultAllow()
    else:
        return PermissionResultDeny()


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
        raise HTTPException(status_code=400, detail="Session not initialized. Call /initialize first.")

    async def event_generator():
        session_state.permission_queue = asyncio.Queue()
        event_queue = asyncio.Queue()
        query_done = asyncio.Event()

        async def permission_monitor():
            while not query_done.is_set():
                try:
                    perm_req = await asyncio.wait_for(session_state.permission_queue.get(), timeout=0.1)
                    await event_queue.put({
                        "event": "permission_request",
                        "data": json.dumps(perm_req)
                    })
                except asyncio.TimeoutError:
                    continue

        async def run_query():
            try:
                full_prompt = req.prompt

                if req.context:
                    context_parts = []
                    if req.context.get("path"):
                        context_parts.append(f"Current file: {req.context['path']}")
                    if req.context.get("selection") and req.context["selection"].get("text"):
                        context_parts.append(f"Selected code:\n```\n{req.context['selection']['text']}\n```")
                    elif req.context.get("content"):
                        context_parts.append(f"File content:\n```\n{req.context['content']}\n```")

                    if context_parts:
                        full_prompt = "\n\n".join(context_parts) + "\n\n" + req.prompt

                print(f"Querying with prompt: {full_prompt[:100]}...", file=sys.stderr)

                def stderr_callback(message: str):
                    print(f"[SDK STDERR] {message}", file=sys.stderr)

                options = ClaudeAgentOptions(
                    permission_mode="default",
                    can_use_tool=can_use_tool_handler,
                    stderr=stderr_callback,
                    extra_args={"debug-to-stderr": None}
                )

                async with ClaudeSDKClient(options) as client:
                    await client.query(full_prompt)

                    async for message in client.receive_response():
                        msg_type = type(message).__name__
                        print(f"Got message: {msg_type}", file=sys.stderr)

                        if hasattr(message, 'content'):
                            for block in message.content:
                                block_type = type(block).__name__

                                if hasattr(block, 'text'):
                                    await event_queue.put({
                                        "event": "text",
                                        "data": json.dumps({"text": block.text})
                                    })
                                    print(f"Emitted TextBlock: {len(block.text)} chars", file=sys.stderr)

                                elif block_type == 'ToolResultBlock' and hasattr(block, 'content'):
                                    if isinstance(block.content, str):
                                        await event_queue.put({
                                            "event": "tool_result",
                                            "data": json.dumps({"content": block.content})
                                        })
                                        print(f"Emitted ToolResult: {len(block.content)} chars", file=sys.stderr)

                await event_queue.put({"event": "complete", "data": json.dumps({"status": "complete"})})

            except Exception as e:
                print(f"Query error: {str(e)}", file=sys.stderr)
                import traceback
                traceback.print_exc(file=sys.stderr)
                await event_queue.put({"event": "error", "data": json.dumps({"error": str(e)})})
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
    session_state.session_active = False
    session_state.working_dir = None
    session_state.auth_method = None
    session_state.permission_mode = None
    return {"status": "ok"}


@app.get("/health")
async def health():
    return {
        "status": "ok" if session_state.session_active else "not_initialized",
        "working_dir": session_state.working_dir,
        "auth_method": session_state.auth_method
    }


def main():
    port = int(os.environ.get("PORT", 8765))
    host = os.environ.get("HOST", "127.0.0.1")

    uvicorn.run(
        app,
        host=host,
        port=port,
        log_level="info",
        access_log=False
    )


if __name__ == "__main__":
    main()
