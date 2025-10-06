import asyncio
import sys
import os
from claude_agent_sdk import ClaudeSDKClient
from claude_agent_sdk.types import ClaudeAgentOptions, PermissionResultAllow, PermissionResultDeny


async def test_in_generator():
    """Test that mimics our FastAPI server setup"""
    print("\n=== Test: Permission inside async generator ===")

    pending_perms = {}

    async def can_use_tool_handler(tool_name: str, input_data: dict, context):
        request_id = f"test_{tool_name}"
        print(f"Permission requested: {request_id}")
        print(f"  Tool: {tool_name}")
        print(f"  Input: {input_data}")

        # Simulate what our server does - create a future
        future = asyncio.Future()
        pending_perms[request_id] = future

        # Auto-approve after small delay (simulating user clicking approve)
        async def auto_approve():
            await asyncio.sleep(0.1)
            future.set_result(True)
            print(f"  Auto-approved: {request_id}")

        asyncio.create_task(auto_approve())

        # Wait for approval
        result = await future
        del pending_perms[request_id]

        if result:
            perm_result = PermissionResultAllow(updated_input=input_data)
            print(f"  Returning: {perm_result}")
            return perm_result
        else:
            perm_result = PermissionResultDeny(message="Denied")
            print(f"  Returning: {perm_result}")
            return perm_result

    async def event_generator():
        """Mimics our FastAPI event generator"""
        print("Starting event generator...")

        options = ClaudeAgentOptions(
            permission_mode="default",
            can_use_tool=can_use_tool_handler,
            stderr=lambda msg: print(f"[STDERR] {msg}", file=sys.stderr)
        )

        async with ClaudeSDKClient(options) as client:
            await client.query("Create a file called test.txt with 'hello world'")

            async for message in client.receive_response():
                msg_type = type(message).__name__
                yield f"Message: {msg_type}"

                if hasattr(message, 'content'):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            yield f"Text: {block.text[:50]}..."

    try:
        # Consume the generator like FastAPI would
        async for event in event_generator():
            print(f"  Event: {event}")

        print("✅ Test passed!")
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    # Set working directory like our server does
    os.chdir("/Users/tylerlifke/Documents/r-studio-claude-code-addin/python")
    asyncio.run(test_in_generator())
