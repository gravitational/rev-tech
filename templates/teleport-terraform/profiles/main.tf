# Composable demo profile.
#
# One root module, every use case behind an enable_* flag. Pick a preset for
# a prospect archetype, or compose your own:
#
#   export TF_VAR_proxy_address=myorg.teleport.sh
#   export TF_VAR_user=you@company.com
#   terraform init
#   terraform apply -var-file=presets/dev-demo.tfvars
#
# Single-feature demos are presets too: presets/grafana.tfvars,
# presets/postgres.tfvars, etc. Run more than one deployment at a time with
# workspaces: terraform workspace new <name>.
#
# All use cases share one VPC, one state file, one destroy. Demo RBAC
# (user-prefixed roles + local demo user) is on by default — see
# modules/demo-rbac and the demo_user_setup output.

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
      "Profile"              = var.profile_label
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
    "Profile"              = var.profile_label
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

# Teleport DB client CA — consumed by the self-managed database hosts.
data "http" "teleport_db_ca" {
  url = "https://${var.proxy_address}/webapi/auth/export?type=db-client"
}

# The Windows auth-setup binary version must match the cluster; ask the proxy
# which version it is running rather than pinning one by hand.
data "http" "teleport_ping" {
  url = "https://${var.proxy_address}/webapi/ping"
}

# ---------------------------------------------------------------------------
# Demo RBAC — the roles and local user the demo narrative depends on.
# Role names are prefixed with the SE's username so concurrent deployments
# on a shared cluster don't collide. The prod/requester/reviewer trio is
# created only when the prod SSH node (access-request demo) is enabled.
#
# After apply, activate the demo user once:
#   tctl users reset bob        # reset link → set password + MFA
#   tsh login --user=bob --auth=local
# ---------------------------------------------------------------------------
module "demo_rbac" {
  count  = var.create_demo_rbac ? 1 : 0
  source = "../modules/demo-rbac"

  name_prefix    = local.user_prefix
  env            = var.env
  prod_env       = var.enable_ssh_prod ? var.prod_env : null
  team           = var.team
  demo_user_name = var.demo_user_name
}

# ---------------------------------------------------------------------------
# Shared network — one VPC for the whole deployment. The secondary subnet
# and DB subnet group exist only when RDS is enabled.
# ---------------------------------------------------------------------------
module "network" {
  source = "../modules/network"

  name_prefix             = "${local.user_prefix}-${var.env}"
  tags                    = local.resource_tags
  env                     = var.env
  cidr_vpc                = var.cidr_vpc
  cidr_subnet             = var.cidr_subnet
  cidr_public_subnet      = var.cidr_public_subnet
  create_nat_gateway      = var.create_nat_gateway
  create_secondary_subnet = var.enable_rds_mysql
  cidr_secondary_subnet   = var.cidr_secondary_subnet
  create_db_subnet_group  = var.enable_rds_mysql
}

# ---------------------------------------------------------------------------
# Server Access: dev SSH nodes.
# ---------------------------------------------------------------------------
module "ssh_nodes_dev" {
  count  = var.enable_ssh ? 1 : 0
  source = "../modules/ssh-node"

  env           = var.env
  team          = var.team
  user          = var.user
  proxy_address = var.proxy_address
  tags          = local.resource_tags
  agent_count   = var.ssh_dev_count
  ami_id        = data.aws_ami.linux.id
  instance_type = "t3.micro"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

# ---------------------------------------------------------------------------
# Server Access: 1 prod SSH node — invisible without an approved access
# request. Drives the request → approve → session-lock demo flow.
# ---------------------------------------------------------------------------
module "ssh_node_prod" {
  count  = var.enable_ssh_prod ? 1 : 0
  source = "../modules/ssh-node"

  env           = var.prod_env
  team          = var.team
  user          = var.user
  proxy_address = var.proxy_address
  tags          = local.resource_tags
  agent_count   = 1
  ami_id        = data.aws_ami.linux.id
  instance_type = "t3.micro"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

# ---------------------------------------------------------------------------
# Database Access: self-hosted engines (cert auth, no passwords).
# ---------------------------------------------------------------------------
module "postgres" {
  count  = var.enable_postgres ? 1 : 0
  source = "../modules/self-database"

  db_type        = "postgres"
  env            = var.env
  team           = var.team
  user           = var.user
  proxy_address  = var.proxy_address
  teleport_db_ca = data.http.teleport_db_ca.response_body
  ami_id         = data.aws_ami.linux.id
  instance_type  = "t3.small"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "postgres_registration" {
  count         = var.enable_postgres ? 1 : 0
  source        = "../modules/dynamic-registration"
  resource_type = "database"
  name          = "postgres-${var.env}"
  description   = "Self-hosted PostgreSQL for ${var.env}"
  protocol      = "postgres"
  uri           = "localhost:5432"
  ca_cert_chain = module.postgres[0].ca_cert
  labels        = { env = var.env, team = var.team }
}

module "mysql" {
  count  = var.enable_mysql ? 1 : 0
  source = "../modules/self-database"

  db_type        = "mysql"
  env            = var.env
  team           = var.team
  user           = var.user
  proxy_address  = var.proxy_address
  teleport_db_ca = data.http.teleport_db_ca.response_body
  ami_id         = data.aws_ami.linux.id
  instance_type  = "t3.small"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "mysql_registration" {
  count         = var.enable_mysql ? 1 : 0
  source        = "../modules/dynamic-registration"
  resource_type = "database"
  name          = "mysql-${var.env}"
  description   = "Self-hosted MySQL (MariaDB) for ${var.env}"
  protocol      = "mysql"
  uri           = "localhost:3306"
  ca_cert_chain = module.mysql[0].ca_cert
  labels        = { env = var.env, team = var.team }
}

module "mongodb" {
  count  = var.enable_mongodb ? 1 : 0
  source = "../modules/self-database"

  db_type        = "mongodb"
  env            = var.env
  team           = var.team
  user           = var.user
  proxy_address  = var.proxy_address
  teleport_db_ca = data.http.teleport_db_ca.response_body
  ami_id         = data.aws_ami.linux.id
  instance_type  = "t3.small"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "mongodb_registration" {
  count         = var.enable_mongodb ? 1 : 0
  source        = "../modules/dynamic-registration"
  resource_type = "database"
  name          = "mongodb-${var.env}"
  description   = "Self-hosted MongoDB for ${var.env}"
  protocol      = "mongodb"
  uri           = "localhost:27017"
  ca_cert_chain = module.mongodb[0].ca_cert
  labels        = { env = var.env, team = var.team }
}

module "cassandra" {
  count  = var.enable_cassandra ? 1 : 0
  source = "../modules/self-database"

  db_type        = "cassandra"
  env            = var.env
  team           = var.team
  user           = var.user
  proxy_address  = var.proxy_address
  teleport_db_ca = data.http.teleport_db_ca.response_body
  ami_id         = data.aws_ami.linux.id
  instance_type  = "t3.medium" # Cassandra JVM needs the headroom

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "cassandra_registration" {
  count         = var.enable_cassandra ? 1 : 0
  source        = "../modules/dynamic-registration"
  resource_type = "database"
  name          = "cassandra-${var.env}"
  description   = "Self-hosted Cassandra for ${var.env}"
  protocol      = "cassandra"
  uri           = "localhost:9042"
  ca_cert_chain = module.cassandra[0].ca_cert
  labels        = { env = var.env, team = var.team }
}

# ---------------------------------------------------------------------------
# Database Access: RDS MySQL with IAM auth + auto user provisioning.
# ---------------------------------------------------------------------------
module "rds_mysql" {
  count  = var.enable_rds_mysql ? 1 : 0
  source = "../modules/rds-mysql"

  env                  = var.env
  team                 = var.team
  user                 = var.user
  proxy_address        = var.proxy_address
  region               = var.region
  ami_id               = data.aws_ami.linux.id
  vpc_id               = module.network.vpc_id
  db_subnet_group_name = module.network.db_subnet_group_name
  subnet_id            = module.network.subnet_id
  security_group_ids   = [module.network.security_group_id]
}

# ---------------------------------------------------------------------------
# Application Access: Grafana (JWT identity injection).
# ---------------------------------------------------------------------------
module "grafana" {
  count  = var.enable_grafana ? 1 : 0
  source = "../modules/app-grafana"

  env           = var.env
  team          = var.team
  user          = var.user
  proxy_address = var.proxy_address
  ami_id        = data.aws_ami.linux.id
  instance_type = "t3.small"
  tags          = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "grafana_registration" {
  count                = var.enable_grafana ? 1 : 0
  source               = "../modules/dynamic-registration"
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
# Application Access: HTTPBin (raw header / JWT inspection).
# ---------------------------------------------------------------------------
module "httpbin" {
  count  = var.enable_httpbin ? 1 : 0
  source = "../modules/app-httpbin"

  env           = var.env
  team          = var.team
  user          = var.user
  proxy_address = var.proxy_address
  ami_id        = data.aws_ami.linux.id
  instance_type = "t3.micro"
  tags          = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "httpbin_registration" {
  count                = var.enable_httpbin ? 1 : 0
  source               = "../modules/dynamic-registration"
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
# Application Access: Flask demo panel (shows the user's Teleport identity).
# ---------------------------------------------------------------------------
module "demo_panel" {
  count  = var.enable_demo_panel ? 1 : 0
  source = "../modules/app-demo-panel"

  env           = var.env
  team          = var.team
  user          = var.user
  proxy_address = var.proxy_address
  app_repo      = var.demo_panel_app_repo
  ami_id        = data.aws_ami.linux.id
  instance_type = "t3.micro"
  tags          = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "demo_panel_registration" {
  count         = var.enable_demo_panel ? 1 : 0
  source        = "../modules/dynamic-registration"
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

# ---------------------------------------------------------------------------
# Application Access: AWS Console federation.
# ---------------------------------------------------------------------------
module "aws_console_host" {
  count  = var.enable_aws_console ? 1 : 0
  source = "../modules/app-aws-console-host"

  user                 = var.user
  proxy_address        = var.proxy_address
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
# Desktop Access: Windows Server + desktop service (browser-based RDP).
# ---------------------------------------------------------------------------
module "windows_instance" {
  count  = var.enable_windows ? 1 : 0
  source = "../modules/windows-instance"

  env              = var.env
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = jsondecode(data.http.teleport_ping.response_body).server_version
  ami_id           = data.aws_ami.windows_server.id
  instance_type    = "t3.medium"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "desktop_service" {
  count  = var.enable_windows ? 1 : 0
  source = "../modules/desktop-service"

  env           = var.env
  team          = var.team
  user          = var.user
  proxy_address = var.proxy_address
  ami_id        = data.aws_ami.linux.id
  instance_type = "t3.small"

  subnet_id            = module.network.subnet_id
  security_group_ids   = [module.network.security_group_id]
  windows_internal_dns = module.windows_instance[0].private_dns
  windows_hosts = [
    {
      name    = module.windows_instance[0].hostname
      address = "${module.windows_instance[0].private_ip}:3389"
    }
  ]
}

# ---------------------------------------------------------------------------
# Machine ID: MCP stdio bot (AI/Claude access with audit + RBAC).
# ---------------------------------------------------------------------------
resource "random_string" "bot_suffix" {
  length  = 4
  upper   = false
  special = false
}

module "mcp_app" {
  count  = var.enable_mcp ? 1 : 0
  source = "../modules/mcp-stdio-app"

  env             = var.env
  team            = var.team
  user            = var.user
  proxy_address   = var.proxy_address
  ami_id          = data.aws_ami.linux.id
  instance_type   = "t3.small"
  app_name        = "mcp-filesystem"
  app_description = "MCP filesystem demo server"
  tags            = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "mcp_registration" {
  count         = var.enable_mcp ? 1 : 0
  source        = "../modules/dynamic-registration"
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
  count  = var.enable_mcp ? 1 : 0
  source = "../modules/machineid-bot"

  bot_name       = "mcp-bot-${random_string.bot_suffix.result}"
  role_name      = "mcp-bot-role-${var.env}"
  allowed_logins = []
  node_labels    = {}
  app_labels = {
    env                              = [var.env]
    team                             = [var.team]
    "teleport.internal/app-sub-kind" = ["mcp"]
  }
  # Read-only tool allowlist — AI agents get read-only by default; write
  # tools (write_file, edit_file, move_file, ...) are denied by policy.
  # Pairs with the :ro volume mount on the MCP container. Good demo beat:
  # ask the client to write a file and show the denial in the audit log.
  mcp_tools = ["read_*", "list_*", "search_files", "get_file_info", "directory_tree"]
}

# ---------------------------------------------------------------------------
# Machine ID: Ansible bot — certificate-based automation, no static keys.
# ---------------------------------------------------------------------------
module "ansible" {
  count  = var.enable_ansible ? 1 : 0
  source = "../modules/machineid-ansible"

  env           = var.env
  team          = var.team
  user          = var.user
  proxy_address = var.proxy_address

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
