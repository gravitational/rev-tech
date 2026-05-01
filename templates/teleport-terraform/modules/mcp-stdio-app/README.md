# MCP Stdio App Module

Deploys an EC2 instance running the Teleport Application Service configured to discover dynamically registered MCP apps by labels.

## Usage

```hcl
module "mcp_stdio_app" {
  source = "../../modules/mcp-stdio-app"

  env              = "dev"
  user             = "engineer@example.com"
  proxy_address    = "teleport.example.com"
  teleport_version = "18.6.4"

  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.small"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]

  app_name        = "mcp-filesystem"
  app_description = "MCP stdio demo server"
  mcp_command     = "docker"
  mcp_args        = ["run", "-i", "--rm", "mcp/everything"]
}
```

## Notes
- This module configures only the App Service host (`app_service.resources` label matching).
- Register MCP apps separately using `teleport_app` (for example via `modules/dynamic-registration`).
- Ensure the host has the tools needed to execute the MCP command (e.g., `docker`) and the runtime user exists.
