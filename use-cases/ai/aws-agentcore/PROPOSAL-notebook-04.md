# Notebook 04: TTI User Identity — Summary

| Notebook | What it proves |
|:---------|:---------------|
| 01 | Lambda tools reachable via Teleport MCP proxy |
| 02 | Teleport identity injected into every tool call |
| 03 | Cedar policy controls which tools a Teleport role can call |
| **04** | **AWS API calls from the tool Lambda are audited as the user, not the agent** |

Implementation: `04-tti-user-identity.ipynb`

Design notes and architectural decisions: `PROPOSAL-tti-lambda-identity.md`
