# MCP Stdio App Module

Deploys an EC2 instance running the Teleport Application Service configured to discover dynamically registered MCP apps by labels.

## Usage

```hcl
module "mcp_stdio_app" {
  source = "../../modules/mcp-stdio-app"

  env              = "dev"
  user             = "engineer@example.com"
  proxy_address    = "teleport.example.com"

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
- Optional streamable-HTTP app: set `http_app_name` (e.g. `"mcp-everything"`) and the host also runs the everything server (`http_mcp_package`, pinned) on `localhost:3000/mcp` and selects apps labelled `teleport.dev/app: <http_app_name>`. Register the app with `uri = "mcp+http://localhost:3000/mcp"` and that same label, or no app service claims it. Unlike a stdio app, an HTTP MCP app can be consumed by a Machine ID bot through tbot's application-tunnel.
- Optional built-in demo server: `mcp_demo_server = true` adds `mcp_demo_server: true` to `app_service`, registering Teleport's `teleport-mcp-demo` (tools `teleport_user_info`, `teleport_session_info`, `teleport_demo_info`). It carries only the `teleport.internal/resource-type: demo` label, so grant it with a role matching that label.
