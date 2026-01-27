# Machine ID + MCP (stdio)

This template deploys a Teleport Application Service running a stdio-based MCP server and provisions a Machine ID bot for automated access.

It follows the official [MCP stdio enrollment guide](https://goteleport.com/docs/enroll-resources/mcp-access/enrolling-mcp-servers/stdio/).

---

## What It Deploys

- 1 EC2 instance running Teleport Application Service with an MCP stdio server
- A Machine ID bot and role scoped to MCP access (`mcp.tools = ["*"]`)
- Shared VPC/subnet/security group baseline

---

## Usage

1. Authenticate to your Teleport cluster:

```bash
tsh login --proxy=teleport.example.com --auth=example
eval $(tctl terraform env)
```

2. Set variables (preferred) or use a tfvars file:

```bash
export TF_VAR_user="engineer@example.com"
export TF_VAR_proxy_address="teleport.example.com"
export TF_VAR_teleport_version="18.6.4"
export TF_VAR_region="us-east-2"
export TF_VAR_env="dev"
export TF_VAR_team="platform"
```

Or:

```bash
cp terraform.tfvars.example terraform.tfvars
```

3. Deploy:

```bash
terraform init
terraform apply
```

4. Access MCP servers:

```bash
tsh mcp ls
tsh mcp config mcp-everything
```

Use the `tsh mcp config` output to configure your MCP client (Claude Desktop, Cursor, etc.).

---

## Notes

- The MCP server is launched via `docker run -i --rm mcp/everything` on the Application Service host.
- MCP stdio enrollment requires Teleport v18.1.0+.
- The Machine ID bot token is exposed as a Terraform output for automated clients.
- To use the bot, configure `tbot` with the token and grant access using `app_labels` and `mcp.tools`.
