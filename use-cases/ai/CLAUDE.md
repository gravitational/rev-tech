# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A monorepo demonstrating Teleport's agentic identity and multi-agent workflows. Multiple specialized AI agents (workers) each operate with their own Machine ID credentials ("digital twin") via tbot sidecars, accessing infrastructure through Teleport separately from the user's identity. Agents communicate using the Google A2A (Agent-to-Agent) protocol over HTTP/JSON-RPC.

Key capabilities:

- **Teleport App Access discovery** -- the orchestrator can discover workers dynamically via `tsh apps ls` with label selectors, or use static URLs.
- **Inter-agent auth** -- the orchestrator's tbot sidecar creates application-tunnel connections to each worker through Teleport, authenticating with its own bot identity.
- **Configurable LLM** -- a shared factory (`packages/shared/src/llm.ts`) supports Google Gemini, Anthropic Claude, OpenAI, and Ollama backends via `LLM_PROVIDER` env var.
- **Agent identity metadata** -- each worker's Agent Card includes `TbotIdentityInfo` describing its bot name and tbot services, surfaced in the frontend.
- **Teleport MCP Access disovery** -- a worker agent can discover MCPs dynamically via `tsh mcp ls`.

**Architecture flow:** User authenticates via Teleport -> accesses React frontend via App Access -> backend validates Teleport JWT assertion token -> forwards prompts to orchestrator via A2A -> orchestrator decomposes tasks and delegates to specialized worker agents -> each worker uses its own tbot sidecar credentials to access resources (SSH, databases, Kubernetes, applications) through Teleport.

### Services

- **web-frontend** -- React 19 frontend (Vite, styled-components, Tanstack Query) with SSE streaming chat UI and agent identity panel
- **backend** -- Node.js/Koa BFF that serves the web app, validates Teleport JWT tokens, and proxies to orchestrator via A2A client
- **orchestrator** -- LangGraph-based agent that discovers workers (static URLs or Teleport App Access), converts each to a LangChain tool, and routes tasks to appropriate workers
- **agent-ssh** -- SSH command execution worker (port 8081), uses tbot ssh-multiplexer
- **agent-quotes** -- Quotes API worker (port 8082), uses tbot application-tunnel
- **agent-db** -- Database query worker (port 8083), uses tbot database-tunnel
- **agent-k8s** -- Kubernetes operations worker (port 8084), uses tbot kubernetes/v2
- **agent-mcp** -- MCP bridge worker (port 8085), dynamically discovers MCP servers via `tsh mcp ls` and bridges their tools using tbot identity

## Skills

This project includes Claude Code skills for working with Teleport:

- **`.claude/skills/tbot.md`** -- Teleport Machine & Workload Identity agent (CLI). Covers all output types (identity, database, kubernetes, application, workload-identity-*), service types (tunnels, proxies, SPIFFE Workload API), Kubernetes Helm deployment, join methods, SPIFFE/workload identity setup, and bot management.
- **`.claude/skills/tsh.md`** -- Teleport client CLI for infrastructure access. Covers SSH, database, Kubernetes, application, cloud provider, MCP, and git access through Teleport's proxy. Includes all proxy commands, access requests, headless auth, VNet, and integration patterns with tbot for automated workloads.
- **`.claude/skills/tbot-api.md`** -- Embedding tbot in Go applications. Covers the `embeddedtbot` wrapper package, core `bot.Bot` API, configuration (connection, onboarding, credential lifetime, destinations), `clientcredentials` in-memory credential service, lifecycle management, and patterns for Kubernetes operators, Terraform providers, and custom services.

## Tech Choices

- **Agent communication:** Google A2A protocol (JSON-RPC 2.0 over HTTP, SSE for streaming)
- **LLM framework:** LangChain/LangGraph with ReAct agent pattern
- **Multi-LLM support:** Shared factory supporting Google Gemini, Anthropic Claude, OpenAI, and Ollama
- **Teleport discovery:** Orchestrator discovers workers via Teleport App Access labels or static URLs
