# AGENTS.md

Instructions for all AI agents working on this project.

## Research First

When answering questions or making decisions about Teleport configuration, architecture, CLI usage, or best practices:

1. **Search the official Teleport documentation first** at <https://goteleport.com/docs/> before relying on training data or assumptions.
2. Use the skill files in `.claude/skills/` as quick references for CLI flags and patterns, but cross-check against live docs when uncertain.
3. If the docs and skills disagree, the official docs at <https://goteleport.com/docs/> are the source of truth.

## Key Documentation Pages

- Teleport overview: <https://goteleport.com/docs/>
- CLI references: <https://goteleport.com/docs/reference/cli/>
  - `tctl`: <https://goteleport.com/docs/reference/cli/tctl/>
  - `tsh`: <https://goteleport.com/docs/reference/cli/tsh/>
  - `tbot`: <https://goteleport.com/docs/reference/cli/tbot/>
  - `teleport`: <https://goteleport.com/docs/reference/cli/teleport/>
  - `fdpass-teleport`: <https://goteleport.com/docs/reference/cli/fdpass-teleport/>
- Workload Identity / SPIFFE: <https://goteleport.com/docs/machine-workload-identity/workload-identity/>
- Access Controls: <https://goteleport.com/docs/access-controls/>
- Application Access: <https://goteleport.com/docs/enroll-resources/application-access/getting-started/>
- Database Access: <https://goteleport.com/docs/enroll-resources/database-access/>
- Kubernetes Access: <https://goteleport.com/docs/enroll-resources/kubernetes-access/>
- Server Access (SSH): <https://goteleport.com/docs/enroll-resources/server-access/getting-started/>

## Available Skills

This project has detailed CLI skill files in `.claude/skills/`:

| Skill | Covers |
| ------- | -------- |
| `tctl.md` | Cluster admin: resources, users, bots, tokens, auth, locks, SSO, plugins |
| `tsh.md` | Client CLI: SSH, databases, Kubernetes, apps, MCP, cloud providers |
| `tbot.md` | Machine identity agent: outputs, tunnels, SPIFFE, Helm, join methods |
| `tbot-api.md` | Embedding tbot in Go: embeddedtbot, bot.Bot, credentials, lifecycle |
| `teleport.md` | Server daemon: service roles, start/configure, integrations, backend |
| `fdpass-teleport.md` | SSH fd-passing helper for tbot ssh-multiplexer |

## Guidelines

- Do not guess Teleport resource configurations. Look them up or ask the user for clarification.
- Do not fabricate `tctl`, `tsh`, `tbot`, `fdpass-teleport` or `teleport` flags. Verify against the skill files or run `--help`.
- When writing tbot configs, use the `v2` config format with `services` (not the legacy `outputs`).
- Prefer `tbot start <subcommand>` CLI flags for simple setups; use config files for multi-output deployments.
- All agents in this project use tbot sidecars for identity -- never hardcode credentials.
