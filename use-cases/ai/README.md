# AI Use Cases — Teleport Identity for MCP

This directory contains demos that show how Teleport integrates with AI tooling.

## Demos

### [mcp-auth-basic](mcp-auth-basic/README.md)

The foundational layer. Demonstrates how Teleport issues a JWT when a developer runs `tsh mcp connect` and how an MCP backend verifies it using FastMCP's `JWTVerifier` against Teleport's JWKS endpoint.

**Run with:** [`mcp-auth-basic/jwt-verification.ipynb`](mcp-auth-basic/jwt-verification.ipynb)

Each demo has its own `README.md` with setup steps and a `.env.example` to configure before running. Many demos also include a Jupyter notebook (`.ipynb`) for an interactive step-by-step walkthrough — where a notebook exists it is the recommended way to run the demo; otherwise the `README.md` outlines the steps directly.