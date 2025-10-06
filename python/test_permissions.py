import asyncio
import sys
from claude_agent_sdk import ClaudeSDKClient
from claude_agent_sdk.types import ClaudeAgentOptions, PermissionResultAllow, PermissionResultDeny


async def test_permission_allow_with_input():
    """Test approving permission with updated_input set"""
    print("\n=== Test 1: Allow with updated_input ===")

    async def can_use_tool_handler(tool_name: str, input_data: dict, context):
        print(f"Permission requested for {tool_name}")
        print(f"Input data: {input_data}")

        result = PermissionResultAllow(updated_input=input_data)
        print(f"Returning: {result}")
        print(f"  behavior: {result.behavior}")
        print(f"  updated_input: {result.updated_input}")
        return result

    options = ClaudeAgentOptions(
        permission_mode="default",
        can_use_tool=can_use_tool_handler,
        stderr=lambda msg: print(f"[STDERR] {msg}", file=sys.stderr)
    )

    try:
        async with ClaudeSDKClient(options) as client:
            await client.query("Create a file called test.txt with 'hello world'")

            async for message in client.receive_response():
                print(f"Message: {type(message).__name__}")

        print("✅ Test passed!")
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()


async def test_permission_allow_without_input():
    """Test approving permission without updated_input (None)"""
    print("\n=== Test 2: Allow without updated_input ===")

    async def can_use_tool_handler(tool_name: str, input_data: dict, context):
        print(f"Permission requested for {tool_name}")

        result = PermissionResultAllow()
        print(f"Returning: {result}")
        print(f"  behavior: {result.behavior}")
        print(f"  updated_input: {result.updated_input}")
        return result

    options = ClaudeAgentOptions(
        permission_mode="default",
        can_use_tool=can_use_tool_handler,
        stderr=lambda msg: print(f"[STDERR] {msg}", file=sys.stderr)
    )

    try:
        async with ClaudeSDKClient(options) as client:
            await client.query("Create a file called test.txt with 'hello world'")

            async for message in client.receive_response():
                print(f"Message: {type(message).__name__}")

        print("✅ Test passed!")
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()


async def test_permission_deny():
    """Test denying permission"""
    print("\n=== Test 3: Deny ===")

    async def can_use_tool_handler(tool_name: str, input_data: dict, context):
        print(f"Permission requested for {tool_name}")

        result = PermissionResultDeny(message="User denied permission")
        print(f"Returning: {result}")
        print(f"  behavior: {result.behavior}")
        print(f"  message: {result.message}")
        return result

    options = ClaudeAgentOptions(
        permission_mode="default",
        can_use_tool=can_use_tool_handler,
        stderr=lambda msg: print(f"[STDERR] {msg}", file=sys.stderr)
    )

    try:
        async with ClaudeSDKClient(options) as client:
            await client.query("Create a file called test.txt with 'hello world'")

            async for message in client.receive_response():
                print(f"Message: {type(message).__name__}")

        print("✅ Test passed!")
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()


async def main():
    print("Testing ClaudeSDKClient permission handling...")
    print(f"Working directory: {os.getcwd()}")

    await test_permission_allow_with_input()
    await test_permission_allow_without_input()
    await test_permission_deny()

    print("\n=== All tests complete ===")


if __name__ == "__main__":
    import os
    asyncio.run(main())
