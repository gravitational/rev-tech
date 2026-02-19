import json
import chainlit as cl
import httpx
from mcp import ClientSession

OLLAMA_URL = "http://localhost:11434/v1/chat/completions"
MODEL = "qwen2.5:7b"

SYSTEM_PROMPT = (
    "You are a helpful assistant. "
    "Only call tools if they are strictly necessary to answer the user's question. "
    "If the user greets you or asks a general question, respond directly."
)


# ---------------------------------------------------------------------
# MCP connection: expose tools to Ollama
# ---------------------------------------------------------------------

@cl.on_mcp_connect
async def on_mcp_connect(connection, session: ClientSession):
    result = await session.list_tools()

    tools = []
    for t in result.tools:
        tools.append({
            "type": "function",
            "function": {
                "name": t.name,
                "description": t.description or "",
                "parameters": t.inputSchema or {
                    "type": "object",
                    "properties": {}
                },
            }
        })

    cl.user_session.set("ollama_tools", tools)


# ---------------------------------------------------------------------
# Tool execution (FastMCP)
# ---------------------------------------------------------------------

@cl.step(type="tool")
async def execute_tool(tool_call, messages):
    tool_name = tool_call["function"]["name"]

    raw_args = tool_call["function"].get("arguments", {})

    # Normalize arguments
    if isinstance(raw_args, str):
        try:
            tool_args = json.loads(raw_args)
        except json.JSONDecodeError:
            tool_args = {}
    elif isinstance(raw_args, dict):
        tool_args = raw_args
    else:
        tool_args = {}

    step = cl.context.current_step
    step.name = tool_name

    mcp_session, _ = next(iter(cl.context.session.mcp_sessions.values()))

    try:
        result = await mcp_session.call_tool(
            tool_name,
            arguments=tool_args
        )

        # 🔑 Extract actual tool payload
        tool_output = result.content[0].text

        step.output = tool_output

    except Exception as e:
        tool_output = json.dumps({"error": str(e)})
        step.output = tool_output

    messages.append({
        "role": "tool",
        "tool_name": tool_name,
        "content": tool_output,
    })


# ---------------------------------------------------------------------
# Simple heuristic: when tools are allowed
# ---------------------------------------------------------------------

def needs_tools(user_text: str) -> bool:
    keywords = [
        "list", "get", "create", "delete", "update",
        "fetch", "describe", "show", "find"
    ]
    text = user_text.lower()
    return any(word in text for word in keywords)


# ---------------------------------------------------------------------
# Chat loop
# ---------------------------------------------------------------------

@cl.on_message
async def main(message: cl.Message):
    msg = cl.Message(content="")
    await msg.send()

    tools = cl.user_session.get("ollama_tools", [])

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": message.content},
    ]

    async with httpx.AsyncClient(timeout=None) as client:
        while True:
            assistant_text = ""
            tool_called = False

            payload = {
                "model": MODEL,
                "messages": messages,
                "stream": True,
            }

            if needs_tools(message.content):
                payload["tools"] = tools
                payload["tool_choice"] = "auto"

            response = await client.post(
                OLLAMA_URL,
                json=payload,
                headers={"Content-Type": "application/json"},
            )

            async for line in response.aiter_lines():
                if not line or not line.startswith("data:"):
                    continue

                data = line.removeprefix("data:").strip()

                if data == "[DONE]":
                    break

                event = json.loads(data)
                choice = event["choices"][0]
                delta = choice.get("delta", {})

                # Stream assistant text
                if "content" in delta:
                    token = delta["content"]
                    assistant_text += token
                    await msg.stream_token(token)

                # Tool calls
                if "tool_calls" in delta:
                    tool_called = True
                    for call in delta["tool_calls"]:
                        await execute_tool(call, messages)

            if not tool_called:
                messages.append({
                    "role": "assistant",
                    "content": assistant_text,
                })
                break

    await msg.update()

