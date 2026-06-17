# AI Use Cases — Teleport Identity for MCP

This directory contains demos that show how Teleport integrates with AI tooling.

## Demos

### [mcp-auth-basic](mcp-auth-basic/README.md)

The foundational layer. Demonstrates how Teleport issues a JWT when a developer runs `tsh mcp connect` and how an MCP backend verifies it using FastMCP's `JWTVerifier` against Teleport's JWKS endpoint.

**Run with:** [`mcp-auth-basic/jwt-verification.ipynb`](mcp-auth-basic/jwt-verification.ipynb)

### [aws-agentcore](aws-agentcore/README.md)

Extends the foundational JWT verification pattern to AWS Bedrock AgentCore Gateway. Teleport acts as the OIDC identity provider, and a REQUEST interceptor Lambda decodes the Teleport JWT and injects the caller's verified identity into every tool call. A third notebook adds policy enforcement via Amazon Verified Permissions (Cedar), with a live policy change demo that requires no Lambda redeployment.

**Run with:** [`aws-agentcore/01-teleport-agentcore-identity-demo.ipynb`](aws-agentcore/01-teleport-agentcore-identity-demo.ipynb) → `02` → `03`

---

Each demo has its own `README.md` with setup steps and a `.env.example` to configure before running. Many demos also include a Jupyter notebook (`.ipynb`) for an interactive step-by-step walkthrough — where a notebook exists it is the recommended way to run the demo; otherwise the `README.md` outlines the steps directly.