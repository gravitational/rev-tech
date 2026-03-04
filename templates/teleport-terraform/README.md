# Teleport Terraform Templates

Repository of Terraform templates and reusable modules that Solution Engineers can use to demonstrate Teleport features on AWS.

**Configuration:** use `export TF_VAR_*` for inputs (preferred) rather than static `terraform.tfvars` files, to mirror all templates in this repo.

## Layout

```
templates/teleport-terraform/
├── control-plane/    # control plane blueprints (EKS, roles, SSO, etc.)
├── data-plane/       # individual use case demos (one Teleport feature per template)
├── profiles/         # multi-use-case compositions for prospect archetypes
├── modules/          # shared building blocks (networking, nodes, dbs, apps, desktop)
└── tools/            # validation, smoke tests, and OPA policy checks
```

**When to use data-plane vs. profiles:**
- **data-plane**: demo a single Teleport feature. Each template creates its own VPC.
- **profiles**: demo multiple features together for a specific prospect archetype. All use cases share one VPC, one `terraform apply`, one `terraform destroy`.

## Templates

### Control Plane

- **control-plane/eks** – EKS-based Teleport control plane split into four layers: infra, Teleport, RBAC, and plugins (Slack access request plugin).
- **control-plane/proxy-peer** – Self-hosted Teleport cluster with proxy peering (Linux).
- **control-plane/cloud** – Teleport Cloud tenant configuration (Teleport provider only).

### Data Plane

- **data-plane/server-access-ssh-getting-started** – Teleport SSH service on Amazon Linux (getting started guide).
- **data-plane/application-access-grafana** – Grafana app access with JWT integration.
- **data-plane/application-access-httpbin** – HTTPBin app access for quick testing.
- **data-plane/application-access-aws-console** – Shared app host with one or more AWS Console apps (shared-account safe defaults).
- **data-plane/database-access-mysql-self-managed** – self-hosted MySQL/MariaDB on EC2.
- **data-plane/database-access-postgres-self-managed** – self-hosted PostgreSQL on EC2.
- **data-plane/database-access-mongodb-self-managed** – self-hosted MongoDB on EC2.
- **data-plane/database-access-rds-mysql** – RDS MySQL with Teleport registration.
- **data-plane/desktop-access-windows-local** – Windows Desktop Access (local users).
- **data-plane/machine-id-ansible** – Machine ID bot + Ansible automation host.
- **data-plane/machine-id-mcp** – MCP stdio server + Machine ID bot for automated access.
- **data-plane/kubernetes-access-eks-autodiscovery** – EKS auto-discovery agent; tag clusters to enroll them automatically.
- **data-plane/server-access-ec2-autodiscovery** – EC2 auto-discovery via SSM + IAM joining; tag instances to enroll them automatically.

More templates can be added over time using the common modules in this directory.

## Profiles

Pre-composed multi-use-case stacks for common prospect archetypes. See [profiles/README.md](profiles/README.md).

- **profiles/windows-mongodb-ssh** – SSH + MongoDB + Windows Desktop. Traditional enterprise archetype.
- **profiles/cloud-native-apps** – Grafana + HTTPBin + RDS MySQL + AWS Console. Modern cloud-native archetype.
- **profiles/full-platform** – All use cases. Full POC / all-up demo environment.

Deploy any profile with three env vars and `terraform apply`. A `connection_guide` output prints all relevant `tsh` commands.

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
- **kube-discovery-agent** – EC2 agent with Teleport kubernetes + discovery services; auto-enrolls tagged EKS clusters.
- **ec2-discovery-agent** – Teleport Discovery Service agent that auto-enrolls tagged EC2 instances via SSM + IAM joining.
- **dynamic-registration** – reusable `teleport_*` resource registration helpers.

Each module includes its own README with usage and variable details.

## Tools

- `tools/terraform-templates-check.sh` – runs `terraform fmt -check` and `terraform validate` per template. Optional: `RUN_TERRAFORM_PLAN=1` for plan checks; `RUN_CONFTEST=1` for OPA policy checks.
- `tools/smoke-test.sh` – deploy, verify via `tsh`, and destroy a single data-plane template end-to-end.
- `tools/smoke-test-all.sh` – batch smoke test runner with `--quick`, `--full`, and `--templates=` modes.
- `tools/policy/` – OPA/Conftest policies enforcing security invariants (IMDSv2, EBS encryption, no public IPs, Teleport label conventions, IAM wildcards).

### Pre-commit hooks

Install once to run checks automatically on every `git commit`:

```bash
brew install pre-commit terraform-docs tflint
pip install checkov
pre-commit install        # installs hooks into .git/hooks/
pre-commit run --all-files  # run against everything once to baseline
```

### One-click deployment via GitHub Actions

See [`.github/workflows/teleport-demo-deploy.yml`](../../../.github/workflows/teleport-demo-deploy.yml). Requires `AWS_ROLE_ARN` and `TELEPORT_IDENTITY` secrets. Triggered from the Actions tab with no local setup needed.

## AWS Console Note

The shared IAM ownership guidance applies to `data-plane/application-access-aws-console` only.
Other data-plane templates are not expected to manage the same account-global IAM role set.
