# Machine ID + MCP (stdio)

Deploys a Teleport Application Service running a stdio-based MCP server and provisions a Machine ID bot for automated, certificate-based access by AI clients.

**Use case:** Show how AI agents (Claude Desktop, Cursor, etc.) access internal MCP tools through Teleport with no long-lived credentials, RBAC enforcement, and full audit logging.

Follows the official [MCP stdio enrollment guide](https://goteleport.com/docs/enroll-resources/mcp-access/enrolling-mcp-servers/stdio/).

---

## What It Deploys

- 1 EC2 instance (t3.small) running Teleport Application Service with an MCP stdio server
- MCP app registered as `mcp-filesystem-<env>` with `env` + `team` labels
- Machine ID bot and role scoped to MCP access (`mcp.tools = ["*"]`) and matching labels
- Shared VPC/subnet/security group baseline

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_user=you@company.com
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_teleport_version=18.6.4
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

cd data-plane/machine-id-mcp
terraform init
terraform apply
```

Allow 3–5 minutes for the instance to boot and the MCP server to register.

---

## Access

```bash
tsh mcp ls                              # mcp-filesystem-dev
tsh mcp config mcp-filesystem-dev
```

Copy the `tsh mcp config` output into your MCP client configuration (Claude Desktop, Cursor, etc.) to connect.

---

## Demo Points

- **No long-lived credentials** — the Machine ID bot receives short-lived certificates issued by Teleport; the AI client never holds a static API key or password
- **Tool-level RBAC** — the bot role grants access only to specific MCP tool patterns (`mcp.tools = ["*"]` scoped to matching labels); access can be narrowed to individual tools
- **Full audit trail** — every MCP tool call is logged in Teleport's audit log with the bot identity, enabling compliance and incident response
- **Revocable access** — removing the bot from the role immediately cuts off the AI client's access to the MCP server
- **Requires Teleport v18.1.0+**

---

## Teardown

```bash
terraform destroy
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `user` | Your email — used for tagging | **required** |
| `proxy_address` | Teleport proxy hostname | **required** |
| `teleport_version` | Teleport version to install | **required** |
| `env` | Environment label | **required** |
| `team` | Team label | `"platform"` |
| `region` | AWS region | **required** |
| `instance_type` | EC2 instance type | `"t3.small"` |
| `bot_name_prefix` | Prefix for the Machine ID bot name | `"mcp-bot"` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
