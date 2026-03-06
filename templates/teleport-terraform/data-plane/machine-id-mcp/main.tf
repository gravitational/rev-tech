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
  }
}

resource "random_string" "bot_suffix" {
  length  = 4
  upper   = false
  special = false
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "teleport.dev/creator" = var.user
      "env"                  = var.env
      "team"                 = var.team
      "ManagedBy"            = "terraform"
    }
  }
}

provider "teleport" {
  addr = "${var.proxy_address}:443"
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

module "network" {
  source             = "../../modules/network"
  env                = var.env
  cidr_vpc           = var.cidr_vpc
  cidr_subnet        = var.cidr_subnet
  cidr_public_subnet = var.cidr_public_subnet
}

module "mcp_stdio_app" {
  source = "../../modules/mcp-stdio-app"

  env              = var.env
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version

  ami_id             = data.aws_ami.linux.id
  instance_type      = var.instance_type
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]

  app_name        = "mcp-filesystem"
  app_description = "MCP filesystem demo server"
  team            = var.team
}

module "mcp_registration" {
  source = "../../modules/dynamic-registration"

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

module "machineid_bot" {
  source = "../../modules/machineid-bot"

  bot_name       = "${var.bot_name_prefix}-${random_string.bot_suffix.result}"
  role_name      = "mcp-bot-role"
  allowed_logins = []
  node_labels    = {}
  app_labels = {
    env                              = [var.env]
    team                             = [var.team]
    "teleport.internal/app-sub-kind" = ["mcp"]
  }
  mcp_tools = ["*"]
}
