# Agentic Identity Demo -- Teleport Multi-Agent Security

This demo shows how Teleport secures multi-agent AI workflows with per-agent Machine Identity, mTLS between all services, and zero application-level RBAC. Each AI agent operates as its own identity ("digital twin") via tbot sidecars, and all inter-service communication is authenticated and encrypted through Teleport -- no secrets in code, no RBAC logic in the app.

```mermaid
flowchart TB
    User([User])
    AppAccess["App Access<br/><i>teleport-jwt-assertion</i>"]
    Proxy["Teleport Proxy"]

    subgraph frontend["Frontend"]
        Web["Frontend (Chainlit)<br/><i>:5201</i>"]
    end

    subgraph orchestration["Orchestration"]
        Orchestrator["Orchestrator (LangGraph)<br/><i>:8080 · task routing</i>"]
        TbotOrch["tbot<br/><i>application-tunnels · identity</i>"]
    end

    subgraph agents["AI Agents"]
        SSH["agent-ssh<br/><i>:8081</i>"]
        Quotes["agent-quotes<br/><i>:8082</i>"]
        DB["agent-db<br/><i>:8083</i>"]
        K8s["agent-k8s<br/><i>:8084</i>"]
        MCP["agent-mcp<br/><i>:8085</i>"]
    end

    subgraph sidecars["tbot Sidecars (Machine ID)"]
        TbotSSH["tbot<br/><i>ssh-multiplexer</i>"]
        TbotQuotes["tbot<br/><i>application-tunnel</i>"]
        TbotDB["tbot<br/><i>database-tunnel</i>"]
        TbotK8s["tbot<br/><i>kubernetes/v2</i>"]
        TbotMCP["tbot<br/><i>identity</i>"]
    end

    subgraph resources["TPR"]
        SSHNodes["SSH Nodes"]
        QuotesApp["Quotes API<br/><i>:3000</i>"]
        Database["Databases"]
        K8sCluster["K8s Clusters"]
        McpServers["MCP Servers"]
    end

    User -->|"Teleport App Access"| AppAccess
    AppAccess --> Web
    Web -->|"HTTP + SSE"| Proxy
    Proxy -->|"A2A"| Orchestrator
    Orchestrator --- TbotOrch
    TbotOrch -->|"A2A over mTLS"| Proxy
    Proxy -->|"A2A"| SSH
    Proxy -->|"A2A"| Quotes
    Proxy -->|"A2A"| DB
    Proxy -->|"A2A"| K8s
    Proxy -->|"A2A"| MCP

    SSH --- TbotSSH
    Quotes --- TbotQuotes
    DB --- TbotDB
    K8s --- TbotK8s
    MCP --- TbotMCP

    TbotSSH -->|"mTLS"| Proxy
    TbotQuotes -->|"mTLS"| Proxy
    TbotDB -->|"mTLS"| Proxy
    TbotK8s -->|"mTLS"| Proxy
    TbotMCP -->|"mTLS"| Proxy

    Proxy --> SSHNodes
    Proxy --> QuotesApp
    Proxy --> Database
    Proxy --> K8sCluster
    Proxy --> McpServers
```

## Running the Agents

### Prerequisites

- Python ≥ 3.12
- [`uv`](https://docs.astral.sh/uv/) package manager
- One of the following LLM backends:
  - **Anthropic** (default): API key required
  - **Ollama**: running locally (e.g. `ollama run llama3.2`)
  - **LM Studio**: running locally on port `1234`

### Setup

```bash
cd use-cases/ai
cp .env.example .env
# Edit .env — set ANTHROPIC_API_KEY or configure your preferred LLM_PROVIDER
uv sync
```

### Run all agents and the orchestrator

```bash
./scripts/local-run.sh
```

 Logs are written to `/tmp/a2a-demo-logs/`. Press `Ctrl+C` to stop all services.


### Verify General knowledge agent

```bash
# Fetch the agent card
curl http://localhost:9003/.well-known/agent.json

# Ask a question (A2A JSON-RPC)
curl -s http://localhost:9003/ \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "message/send",
    "params": {
      "message": {
        "messageId": "1",
        "role": "user",
        "parts": [{"kind": "text", "text": "Explain how TLS certificates work"}]
      }
    },
    "id": 1
  }' | jq
```

---

## How Teleport Secures This

- **Per-agent Machine Identity** -- Each worker gets its own tbot sidecar with a unique `BOT_NAME`, issuing short-lived certificates via Teleport Machine ID.
- **mTLS everywhere** -- All inter-service calls (backend to orchestrator, orchestrator to workers) go through Teleport tunnels with mutual TLS. No plaintext HTTP between services in production.
- **Zero application RBAC** -- The application contains no authorization code. Teleport roles control which resources each agent can access (SSH nodes, databases, apps, Kubernetes clusters).
- **Full per-agent audit trail** -- Every action by every agent is logged in the Teleport audit log under its own bot identity, giving complete attribution.
