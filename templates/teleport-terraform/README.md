# Teleport Terraform Templates

Repository of Terraform templates and reusable modules that Solution Engineers can use to demonstrate Teleport features on AWS.

**Configuration:** use `export TF_VAR_*` for inputs (preferred) rather than static `terraform.tfvars` files, to mirror all templates in this repo.

## Layout

```
templates/teleport-terraform/
├── control-plane/    # control plane blueprints (EKS, roles, SSO, etc.)
├── data-plane/       # full demo scenarios (applications, databases, nodes)
├── modules/          # shared building blocks (networking, nodes, dbs, apps, desktop)
└── tools/            # validation and smoke tests
```

## Templates

### Control Plane

- **control-plane/eks** – EKS-based Teleport control plane split into infra, Teleport, and RBAC layers.
- **control-plane/proxy-peer** – Self-hosted Teleport cluster with proxy peering (Linux).
- **control-plane/cloud** – Teleport Cloud tenant configuration (Teleport provider only).

### Data Plane

- **data-plane/server-access-ssh-getting-started** – Teleport SSH service on Amazon Linux (getting started guide).
- **data-plane/application-access-grafana** – Grafana app access with JWT integration.
- **data-plane/application-access-httpbin** – HTTPBin app access for quick testing.
- **data-plane/database-access-mysql-self-managed** – self-hosted MySQL/MariaDB on EC2.
- **data-plane/database-access-postgres-self-managed** – self-hosted PostgreSQL on EC2.
- **data-plane/database-access-mongodb-self-managed** – self-hosted MongoDB on EC2.
- **data-plane/database-access-rds-mysql** – RDS MySQL with Teleport registration.
- **data-plane/desktop-access-windows-local** – Windows Desktop Access (local users).
- **data-plane/machine-id-ansible** – Machine ID bot + Ansible automation host.
- **data-plane/machine-id-mcp** – MCP stdio server + Machine ID bot for automated access.

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
