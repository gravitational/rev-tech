# Teleport Terraform Templates

Repository of Terraform templates and reusable modules that Solution Engineers can use to demonstrate Teleport features on AWS.

## Layout

```
templates/teleport-terraform/
├── modules/          # shared building blocks (networking, nodes, dbs, apps, desktop)
└── <template>/       # full demo scenarios (data plane)
```

## Templates

- **server-access-ssh-getting-started** – Teleport SSH service on Amazon Linux (getting started guide).
- **application-access-grafana** – Grafana app access with JWT integration.
- **application-access-httpbin** – HTTPBin app access for quick testing.
- **database-access-mysql-self-managed** – self-hosted MySQL/MariaDB on EC2.
- **database-access-postgres-self-managed** – self-hosted PostgreSQL on EC2.
- **database-access-mongodb-self-managed** – self-hosted MongoDB on EC2.
- **database-access-rds-mysql** – RDS MySQL with Teleport registration.
- **desktop-access-windows-local** – Windows Desktop Access (local users).
- **machine-id-ansible** – Machine ID bot + Ansible automation host.
- **machine-id-mcp** – MCP stdio server + Machine ID bot for automated access.

More templates (e.g., control plane and multi-environment blueprints) can be added over time using the common modules in this directory.

## Modules

- **network** – VPC/subnet/security group scaffolding.
- **ssh-node** – EC2 nodes running Teleport SSH service.
- **self-mysql** – self-hosted MySQL/MariaDB with TLS and Teleport DB agent.
- **self-postgres** – self-hosted PostgreSQL with TLS and Teleport DB agent.
- **self-mongodb** – self-hosted MongoDB with Teleport DB agent.
- **rds-mysql** – RDS MySQL provisioning and wiring.
- **app-grafana** – Grafana app server + Teleport app agent.
- **app-httpbin** – HTTPBin app server + Teleport app agent.
- **windows-instance** – Windows Server host with Teleport Desktop Access prep.
- **desktop-service** – Linux Desktop Service for Windows desktop access.
- **machineid-ansible** – Machine ID + Ansible automation host.
- **machineid-bot** – Machine ID bot, role, and provision token.
- **mcp-stdio-app** – Teleport app service running a stdio MCP server.
- **dynamic-registration** – reusable `teleport_*` resource registration helpers.

Each module includes its own README with usage and variable details.

## Tools

- `templates/teleport-terraform/tools/terraform-templates-check.sh` – runs `terraform fmt -check` and `terraform validate` per template; supports optional plans with `RUN_TERRAFORM_PLAN=1` (requires AWS + Teleport credentials).
