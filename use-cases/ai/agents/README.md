# Agents

This directory contains all A2A specialist agents and the shared infrastructure they build on.

---

## Directory Structure

```
agents/
├── base_agent.py        # Shared executor + BaseA2AAgent class
├── llm.py               # Shared get_llm() factory
├── general_agent/       # General knowledge agent (LM Studio / Ollama)
├── sql_agent/           # Natural language → SQL agent
└── rag_agent/           # Document search agent
```

---

## How It Works

Every agent follows the same pattern:

```
LangGraph graph  +  AgentCard
        │                │
        └──── BaseA2AAgent ────▶ A2AStarletteApplication
                                        │
                              /.well-known/agent.json  (GET)
                              /                        (POST JSON-RPC)
```

### `BaseA2AAgent`

`base_agent.py` wires a compiled LangGraph graph into the A2A protocol:

1. **`LangGraphAgentExecutor`** — implements the A2A `AgentExecutor` interface. On each request it:
   - Extracts text from the incoming A2A message parts
   - Calls `graph.ainvoke({"messages": [HumanMessage(...)]})`
   - Emits the last message as an A2A artifact via `TaskUpdater`
   - Marks the task `completed`

2. **`BaseA2AAgent`** — wraps the executor in `DefaultRequestHandler` + `InMemoryTaskStore`, builds the `A2AStarletteApplication`, and exposes a `.run()` method.

### `llm.py`

Shared LLM factory. Controlled by the `LLM_PROVIDER` environment variable:

| `LLM_PROVIDER` | Backend | Key env vars |
|---|---|---|
| `anthropic` (default) | Anthropic Claude | `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` |
| `lmstudio` | LM Studio (OpenAI-compat) | `LM_STUDIO_BASE_URL`, `LM_STUDIO_MODEL` |
| `ollama` | Ollama | `OLLAMA_BASE_URL`, `OLLAMA_MODEL` |

---

## Adding a New Agent

### 1. Create the directory

```
agents/
└── my_agent/
    ├── __init__.py
    ├── card.json
    ├── graph.py
    └── main.py
```

### 2. Write `card.json`

The card describes your agent to the orchestrator. The `skills[].description` is what the orchestrator LLM reads to decide routing — make it specific.

```json
{
  "name": "My Agent",
  "description": "One sentence on what this agent does and when to use it.",
  "url": "http://localhost:900X",
  "version": "1.0.0",
  "defaultInputModes": ["text"],
  "defaultOutputModes": ["text"],
  "capabilities": { "streaming": false },
  "skills": [
    {
      "id": "my-skill",
      "name": "My Skill Name",
      "description": "Detailed description of what this skill does. Be specific about inputs, outputs, and when to use it vs other agents.",
      "tags": ["tag1", "tag2"],
      "examples": [
        "Example question this agent should handle"
      ]
    }
  ]
}
```

### 3. Write `graph.py`

Return a compiled LangGraph graph. The graph must accept `MessagesState` and return updated messages.

```python
from langgraph.graph import END, MessagesState, StateGraph
from agents.llm import get_llm

def build_graph():
    llm = get_llm()

    def agent_node(state: MessagesState):
        return {"messages": [llm.invoke(state["messages"])]}

    graph = StateGraph(MessagesState)
    graph.add_node("agent", agent_node)
    graph.set_entry_point("agent")
    graph.add_edge("agent", END)
    return graph.compile()
```

For a ReAct agent with tools:

```python
from langchain_core.tools import tool
from langgraph.prebuilt import ToolNode

@tool
def my_tool(input: str) -> str:
    """Tool description — the LLM reads this to decide when to call it."""
    return "result"

def build_graph():
    llm = get_llm().bind_tools([my_tool])

    def agent_node(state: MessagesState):
        return {"messages": [llm.invoke(state["messages"])]}

    def should_continue(state: MessagesState):
        return "tools" if state["messages"][-1].tool_calls else END

    graph = StateGraph(MessagesState)
    graph.add_node("agent", agent_node)
    graph.add_node("tools", ToolNode([my_tool]))
    graph.set_entry_point("agent")
    graph.add_conditional_edges("agent", should_continue)
    graph.add_edge("tools", "agent")
    return graph.compile()
```

### 4. Write `main.py`

```python
import json
import os
from pathlib import Path

from a2a.types import AgentCapabilities, AgentCard, AgentSkill
from agents.base_agent import BaseA2AAgent
from agents.my_agent.graph import build_graph

def load_card() -> AgentCard:
    raw = json.loads((Path(__file__).parent / "card.json").read_text())
    return AgentCard(
        name=raw["name"],
        description=raw["description"],
        url=raw["url"],
        version=raw["version"],
        defaultInputModes=raw["defaultInputModes"],
        defaultOutputModes=raw["defaultOutputModes"],
        capabilities=AgentCapabilities(**raw["capabilities"]),
        skills=[AgentSkill(**s) for s in raw["skills"]],
    )

if __name__ == "__main__":
    port = int(os.environ.get("AGENT_PORT", 900X))
    agent = BaseA2AAgent(graph=build_graph(), card=load_card())
    agent.run(port=port)
```

### 5. Register it

**`agents.json`** — add the agent URL so the orchestrator discovers it in Phase 1:

```json
{ "url": "http://localhost:900X" }
```

**`.devcontainer/docker-compose.yml`** — add a service:

```yaml
my-agent:
  build:
    context: ../
    dockerfile: .devcontainer/Dockerfile
  command: python -m agents.my_agent.main
  ports:
    - "900X:900X"
  environment:
    - ANTHROPIC_API_KEY
    - LLM_PROVIDER
```

### 6. Test it

```bash
# Agent card
curl http://localhost:900X/.well-known/agent.json | jq

# Send a message
curl -s http://localhost:900X/ \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "message/send",
    "params": {
      "message": {
        "messageId": "msg-001",
        "role": "user",
        "parts": [{"kind": "text", "text": "your question here"}]
      }
    },
    "id": 1
  }' | jq
```

---

## Port Assignments

| Agent | Port |
|---|---|
| Orchestrator | 9000 |
| SQL Query Agent | 9001 |
| RAG Search Agent | 9002 |
| General Knowledge Agent | 9003 |
| _(next agent)_ | 9004 |
