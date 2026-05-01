# Profile: Dev Demo
#
# Prospect archetype: any engineering org evaluating Teleport for day-to-day
# developer access. Use this for focused POCs or live demos where you want to
# walk through a realistic "developer day in the life" narrative with two personas.
#
# Demo personas:
#   Bob  (bob@...)  — devs group  → dev-access, dev-requester
#   $USER  ($USER@...)  — engineers   → platform-dev-access, prod-readonly-access,
#                                    prod-requester, prod-reviewer
#
# Demo flow:
#   1.  Bob logs in — sees only dev-labeled resources (2 SSH nodes, postgres,
#       mongodb, grafana, httpbin)
#   2.  Bob SSHs to dev-server-1 — Teleport creates a host user dynamically,
#       session is recorded and streamed to the audit log
#   3.  Bob connects to postgres-dev via `tsh db connect` — no password, cert auth
#   4.  Bob opens Grafana via the web UI — JWT header shows his identity to the app
#   5.  Bob submits an access request for prod-readonly-access
#   6.  $USER receives a Slack notification, reviews, approves
#   7.  Bob now sees `prod-server` in `tsh ls` — nothing else changed in his session
#   8.  Bob SSHs to prod-server — $USER can see the live session and lock it
#   9.  $USER walks through the audit log in the UI to show the full trail
#  10.  $USER demos the Ansible Machine ID bot and MCP AI integration for automation
#
# Demonstrates:
#   Server Access    — SSH to dev and prod nodes, dynamic host users, session recording
#   Database Access  — PostgreSQL + MongoDB (cert auth, no passwords)
#   App Access       — Grafana + HTTPBin (JWT identity injection)
#   Desktop Access   — Windows Server (browser-based RDP via Teleport)
#   Machine ID       — Ansible bot (infra automation), MCP stdio bot (AI/Claude)
#   Access Requests  — Bob requests prod → Slack → $USER approves → session lock
#
# Resource summary (~$5-7/day):
#   SSH nodes: 3 × t3.micro (2 dev + 1 prod)
#   Databases: 2 × t3.small (postgres-dev, mongodb-dev)
#   Apps:      2 × t3.micro + 1 × t3.small (httpbin, mcp-host, grafana)
#   Machine ID: 1 × t3.small (ansible-host, baked into module)
#   Desktop:   1 × t3.medium (Windows) + 1 × t3.small (desktop-service)
#   NAT GW:    ~$1.20/day (fixed)
#
# Optional addition (not included):
#   RDS MySQL — add the rds-mysql module + secondary subnet to show IAM-auth
#   database access (zero passwords, cloud-native pattern). Adds ~$1-2/day.
#
# Deploy:
#   export TF_VAR_proxy_address=myorg.teleport.sh
#   export TF_VAR_user=you@company.com
#   export TF_VAR_teleport_version=18.0.0
#   terraform init && terraform apply
#
# Teardown:
#   terraform destroy

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99"
    }
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 18.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "teleport.dev/creator" = var.user
      "env"                  = var.env
      "team"                 = var.team
      "ManagedBy"            = "terraform"
      "Profile"              = "dev-demo"
    }
  }
}

provider "teleport" {
  addr = "${var.proxy_address}:443"
}

locals {
  user_prefix = lower(split("@", var.user)[0])
  resource_tags = {
    "teleport.dev/creator" = var.user
    "env"                  = var.env
    "Profile"              = "dev-demo"
  }
}

data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "windows_server" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Shared network — one VPC for the whole profile.
# ---------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  name_prefix        = "${local.user_prefix}-${var.env}"
  tags               = local.resource_tags
  env                = var.env
  cidr_vpc           = var.cidr_vpc
  cidr_subnet        = var.cidr_subnet
  cidr_public_subnet = var.cidr_public_subnet
}

data "http" "teleport_db_ca" {
  url = "https://${var.proxy_address}/webapi/auth/export?type=db-client"
}

# ---------------------------------------------------------------------------
# Server Access: 2 dev SSH nodes Bob can reach by default.
# Dynamic host user creation and enhanced session recording are enabled in the
# ssh-node module's teleport.yaml — no static accounts needed on the host.
# ---------------------------------------------------------------------------
module "ssh_nodes_dev" {
  source = "../../modules/ssh-node"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  tags             = local.resource_tags
  agent_count      = 2
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.micro"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

# ---------------------------------------------------------------------------
# Server Access: 1 prod SSH node — Bob cannot see this without approval.
# Used to demonstrate the full access request → approve → lock flow:
#   tsh ls                            # Bob sees only dev nodes
#   tsh request create --roles=prod-readonly-access
#   ($USER approves in Slack)
#   tsh ls                            # prod-server appears
#   tsh ssh ec2-user@prod-server      # session is recorded
#   ($USER locks the session from the Teleport UI)
# ---------------------------------------------------------------------------
module "ssh_node_prod" {
  source = "../../modules/ssh-node"

  env              = var.prod_env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  tags             = local.resource_tags
  agent_count      = 1
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.micro"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

# ---------------------------------------------------------------------------
# Database Access: self-hosted PostgreSQL (dev).
# Teleport issues short-lived client certs — no DB passwords stored anywhere.
# ---------------------------------------------------------------------------
module "postgres" {
  source = "../../modules/self-database"

  db_type          = "postgres"
  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  teleport_db_ca   = data.http.teleport_db_ca.response_body
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.small"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "postgres_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "database"
  name          = "postgres-${var.env}"
  description   = "Self-hosted PostgreSQL for ${var.env}"
  protocol      = "postgres"
  uri           = "localhost:5432"
  ca_cert_chain = module.postgres.ca_cert
  labels        = { env = var.env, team = var.team }
}

# ---------------------------------------------------------------------------
# Database Access: self-hosted MongoDB (dev).
# ---------------------------------------------------------------------------
module "mongodb" {
  source = "../../modules/self-database"

  db_type          = "mongodb"
  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  teleport_db_ca   = data.http.teleport_db_ca.response_body
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.small"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "mongodb_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "database"
  name          = "mongodb-${var.env}"
  description   = "Self-hosted MongoDB for ${var.env}"
  protocol      = "mongodb"
  uri           = "localhost:27017"
  ca_cert_chain = module.mongodb.ca_cert
  labels        = { env = var.env, team = var.team }
}

# ---------------------------------------------------------------------------
# Application Access: Grafana.
# Opens in the browser — Teleport injects a JWT header so Grafana sees the
# user's identity without requiring a separate Grafana login.
# ---------------------------------------------------------------------------
module "grafana" {
  source = "../../modules/app-grafana"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.small"
  tags             = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "grafana_registration" {
  source               = "../../modules/dynamic-registration"
  resource_type        = "app"
  name                 = "grafana-${var.env}"
  description          = "Grafana dashboard for ${var.env}"
  uri                  = "http://localhost:3000"
  public_addr          = "grafana-${var.env}.${var.proxy_address}"
  labels               = { env = var.env, team = var.team, "teleport.dev/app" = "grafana" }
  rewrite_headers      = ["Host: grafana-${var.env}.${var.proxy_address}", "Origin: https://grafana-${var.env}.${var.proxy_address}"]
  insecure_skip_verify = true
}

# ---------------------------------------------------------------------------
# Application Access: HTTPBin.
# A simple HTTP inspector — good for showing request headers Teleport injects
# (X-Forwarded-User, Teleport-Jwt-Assertion, etc.) in raw form.
# ---------------------------------------------------------------------------
module "httpbin" {
  source = "../../modules/app-httpbin"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.micro"
  tags             = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "httpbin_registration" {
  source               = "../../modules/dynamic-registration"
  resource_type        = "app"
  name                 = "httpbin-${var.env}"
  description          = "HTTP inspector — shows Teleport-injected headers"
  uri                  = "http://localhost:80"
  public_addr          = "httpbin-${var.env}.${var.proxy_address}"
  labels               = { env = var.env, team = var.team, "teleport.dev/app" = "httpbin" }
  rewrite_headers      = ["Host: httpbin-${var.env}.${var.proxy_address}", "Origin: https://httpbin-${var.env}.${var.proxy_address}"]
  insecure_skip_verify = true
}

# ---------------------------------------------------------------------------
# Desktop Access: Windows Server.
# Browser-based RDP — no client software, no VPN, full session recording.
# Requires Teleport Desktop Access license.
# ---------------------------------------------------------------------------
module "windows_instance" {
  source = "../../modules/windows-instance"

  env              = var.env
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  ami_id           = data.aws_ami.windows_server.id
  instance_type    = "t3.medium"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "desktop_service" {
  source = "../../modules/desktop-service"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.small"

  subnet_id            = module.network.subnet_id
  security_group_ids   = [module.network.security_group_id]
  windows_internal_dns = module.windows_instance.private_dns
  windows_hosts = [
    {
      name    = module.windows_instance.hostname
      address = "${module.windows_instance.private_ip}:3389"
    }
  ]
}

# ---------------------------------------------------------------------------
# Machine ID: MCP stdio bot.
# Demonstrates AI-driven infrastructure access — Claude (or any MCP client)
# can run tools against live infrastructure through Teleport, with full
# audit logging and RBAC just like a human user.
# Usage: tsh mcp config mcp-filesystem-<env> → paste into Claude Desktop
# ---------------------------------------------------------------------------
resource "random_string" "bot_suffix" {
  length  = 4
  upper   = false
  special = false
}

module "mcp_app" {
  source = "../../modules/mcp-stdio-app"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.small"
  app_name         = "mcp-filesystem"
  app_description  = "MCP filesystem demo server"
  tags             = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "mcp_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "app"
  name          = "mcp-filesystem-${var.env}"
  description   = "MCP filesystem demo server"
  labels = {
    env                              = var.env
    team                             = var.team
    "teleport.internal/app-sub-kind" = "mcp"
  }
  mcp_command          = "docker"
  mcp_args             = ["run", "-i", "--rm", "-v", "/demo-files:/demo-files:ro", "mcp/filesystem", "/demo-files"]
  mcp_run_as_host_user = "docker"
}

module "mcp_bot" {
  source = "../../modules/machineid-bot"

  bot_name       = "mcp-bot-${random_string.bot_suffix.result}"
  role_name      = "mcp-bot-role-${var.env}"
  allowed_logins = []
  node_labels    = {}
  app_labels = {
    env                              = [var.env]
    team                             = [var.team]
    "teleport.internal/app-sub-kind" = ["mcp"]
  }
  mcp_tools = ["*"]
}

# ---------------------------------------------------------------------------
# Machine ID: Ansible bot.
# Demonstrates non-human / service account access — tbot issues short-lived
# SSH certs to the Ansible host at runtime. No static private keys on disk,
# no long-lived credentials.
# ---------------------------------------------------------------------------
module "ansible" {
  source = "../../modules/machineid-ansible"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
