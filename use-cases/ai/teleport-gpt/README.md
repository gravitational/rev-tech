---

# 🚀 teleport-gpt

Teleport-GPT is a **Teleport-themed AI chat interface** built with **Chainlit**, powered by **Ollama**, and connected to **MCP (Model Context Protocol) servers** for tool-aware conversations.

It uses **uv** for modern, fast Python package management and reproducible environments.

---

## 🧠 Architecture Overview

```text
User (Browser)
      ↓
Chainlit UI (Teleport Skin)
      ↓
LangChain + Ollama (Local LLM)
      ↓
MCP Client
      ↓
MCP Servers (Tools / APIs / Integrations)
```

### Stack

* **UI Framework:** Chainlit
* **LLM Runtime:** Ollama
* **Protocol Layer:** Model Context Protocol (MCP)
* **Package Manager:** uv
* **Theme:** Teleport-inspired UI skin

---

## ✨ Features

* 🔐 Teleport-branded chat interface
* 🧠 Local LLM inference via Ollama
* 🔌 MCP integration for tool-aware conversations
* ⚡ Fast dependency management with uv
* 🧱 Modular and extensible architecture
* 🧪 Designed for experimentation with Teleport workflows

---

## 📦 Project Configuration

**`pyproject.toml`**

```toml
name = "teleport-gpt"
version = "0.1.0"
description = "Teleport Chat Interface"
readme = "README.md"
requires-python = ">=3.13"
dependencies = [
    "chainlit>=2.9.3",
    "langchain-ollama>=1.0.1",
]
```

---

## 🛠 Prerequisites

### 1. Install uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Verify:

```bash
uv --version
```

---

### 2. Install Ollama

Install from:

👉 [https://ollama.com](https://ollama.com)

Start Ollama:

```bash
ollama serve
```

Pull a model (example):

```bash
ollama pull qwen2.5:7b 
```

---

## 🚀 Running teleport-gpt

From the project root:

```bash
uv sync
```

Then start the app:

```bash
uv run chainlit run main.py --port 8002
```

Open:

```
http://localhost:8002
```

---

## 🔌 MCP Integration

Teleport-GPT communicates with MCP servers to:

* Execute tools
* Query external APIs
* Interact with Teleport services
* Extend capabilities beyond pure LLM responses

Typical flow:

1. User sends message
2. Ollama model processes input
3. Model determines if tool usage is required
4. MCP client calls appropriate MCP server
5. Response returned to Chainlit UI

---

## 🎨 Teleport Skin

The UI is styled to reflect:

* Teleport brand colors
* Dark-first theme
* Security-centric design cues
* Terminal-inspired interaction

You can customize styling via:

* `.chainlit/config.toml`
* Custom CSS injection
* Theme overrides

---

## 🔧 Development

Run with auto-reload:

```bash
uv run chainlit run main.py --port 8002 --watch
```

Add dependencies:

```bash
uv add <package>
```

Update dependencies:

```bash
uv sync
```
