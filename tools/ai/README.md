# Teleport AI Tooling for Claude Code

A starting point for anyone using [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to develop Teleport-related projects. This directory provides CLI skill files and agent guidelines so Claude can work effectively with the full Teleport toolchain.

## What's Included

### CLI Skill Files (`.claude/skills/`)

Detailed reference guides for every Teleport CLI tool:

| Skill File | CLI Tool | Description |
| --- | --- | --- |
| `tctl.md` | `tctl` | Cluster administration — resources, users, bots, tokens, auth, locks, SSO, plugins |
| `tsh.md` | `tsh` | Client CLI — SSH, databases, Kubernetes, apps, MCP, cloud providers |
| `tbot.md` | `tbot` | Machine identity agent — outputs, tunnels, SPIFFE, Helm, join methods |
| `tbot-api.md` | `tbot` (Go API) | Embedding tbot in Go — `embeddedtbot`, `bot.Bot`, credentials, lifecycle |
| `teleport.md` | `teleport` | Server daemon — service roles, start/configure, integrations, backends |
| `fdpass-teleport.md` | `fdpass-teleport` | SSH fd-passing helper for tbot ssh-multiplexer |

### Agent Guidelines (`AGENTS.md`)

Instructions for AI agents working on Teleport projects, including documentation-first research practices and configuration guidelines.

### Claude Settings (`.claude/settings.local.json`)

Pre-configured permissions for running Teleport CLI tools and fetching official documentation.

## Usage

Copy or symlink the `.claude/` directory and `AGENTS.md` into the root of your Teleport project:

```bash
# Copy
cp -r tools/ai/.claude AGENTS.md /path/to/your/project/

# Or symlink
ln -s /path/to/rev-tech/tools/ai/.claude /path/to/your/project/.claude
ln -s /path/to/rev-tech/tools/ai/AGENTS.md /path/to/your/project/
```

Then open your project with Claude Code. The skill files and settings will be picked up automatically.

## Resources

- [Teleport Documentation](https://goteleport.com/docs/)
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
