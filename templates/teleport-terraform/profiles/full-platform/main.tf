# Profile: Full Platform Demo
#
# Prospect archetype: large enterprise evaluating Teleport across their entire
# stack — infrastructure, databases, internal apps, Windows desktops, and
# machine identity. Use this for POCs with a broad technical audience or for
# an all-up internal demo environment.
#
# Demonstrates:
#   - Server Access: SSH nodes
#   - Database Access: PostgreSQL, MySQL, MongoDB (self-hosted), RDS MySQL
#   - Application Access: Grafana, HTTPBin, AWS Console
#   - Desktop Access: Windows Server
#   - Machine ID: MCP bot (automated access)
#
# Deploy:
#   export TF_VAR_proxy_address=myorg.teleport.sh
#   export TF_VAR_user=you@company.com
#   export TF_VAR_teleport_version=18.0.0
#   terraform init && terraform apply
#
# NOTE: This profile creates significant AWS resources (~$5-10/day).
#       Always destroy when the demo is complete.
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
      "Profile"              = "full-platform"
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
    "Profile"              = "full-platform"
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

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Shared network with secondary subnet for RDS.
# ---------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  name_prefix             = "${local.user_prefix}-${var.env}"
  tags                    = local.resource_tags
  env                     = var.env
  cidr_vpc                = var.cidr_vpc
  cidr_subnet             = var.cidr_subnet
  cidr_public_subnet      = var.cidr_public_subnet
  create_secondary_subnet = true
  cidr_secondary_subnet   = var.cidr_secondary_subnet
  create_db_subnet_group  = true
}

data "http" "teleport_db_ca" {
  url = "https://${var.proxy_address}/webapi/auth/export?type=db-client"
}

# ---------------------------------------------------------------------------
# Server Access: SSH nodes.
# ---------------------------------------------------------------------------
module "ssh_nodes" {
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
# Database Access: self-hosted PostgreSQL.
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
# Database Access: self-hosted MongoDB.
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
# Database Access: RDS MySQL with IAM auth.
# ---------------------------------------------------------------------------
module "rds_mysql" {
  source = "../../modules/rds-mysql"

  env                  = var.env
  team                 = var.team
  user                 = var.user
  proxy_address        = var.proxy_address
  teleport_version     = var.teleport_version
  region               = var.region
  ami_id               = data.aws_ami.linux.id
  vpc_id               = module.network.vpc_id
  db_subnet_group_name = module.network.db_subnet_group_name
  subnet_id            = module.network.subnet_id
  security_group_ids   = [module.network.security_group_id]
}

# ---------------------------------------------------------------------------
# Application Access: Grafana + HTTPBin + AWS Console.
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
  description          = "HTTP test app for ${var.env}"
  uri                  = "http://localhost:80"
  public_addr          = "httpbin-${var.env}.${var.proxy_address}"
  labels               = { env = var.env, team = var.team, "teleport.dev/app" = "httpbin" }
  rewrite_headers      = ["Host: httpbin-${var.env}.${var.proxy_address}", "Origin: https://httpbin-${var.env}.${var.proxy_address}"]
  insecure_skip_verify = true
}

module "demo_panel" {
  source = "../../modules/app-demo-panel"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  app_repo         = var.demo_panel_app_repo
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.micro"
  tags             = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "demo_panel_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "app"
  name          = "demo-panel-${var.env}"
  description   = "Teleport Demo Panel — shows identity injected via JWT header"
  uri           = "http://localhost:5000"
  public_addr   = "demo-panel-${var.env}.${var.proxy_address}"
  labels = {
    env                = var.env
    team               = var.team
    "teleport.dev/app" = "demo-panel"
  }
}

module "aws_console_host" {
  source = "../../modules/app-aws-console-host"

  user                 = var.user
  proxy_address        = var.proxy_address
  teleport_version     = var.teleport_version
  ami_id               = data.aws_ami.linux.id
  instance_type        = "t3.micro"
  tags                 = local.resource_tags
  host_env             = var.env
  host_team            = var.team
  app_env              = var.env
  app_a_name           = "awsconsole-${var.env}"
  app_a_public_addr    = "awsconsole-${var.env}.${var.proxy_address}"
  app_a_uri            = "https://console.aws.amazon.com/ec2/v2/home"
  app_a_aws_account_id = data.aws_caller_identity.current.account_id
  app_a_team           = var.team
  assume_role_arns     = var.console_role_arns

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

# ---------------------------------------------------------------------------
# Desktop Access: Windows Server.
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
