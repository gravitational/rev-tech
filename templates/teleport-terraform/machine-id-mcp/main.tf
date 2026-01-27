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
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "teleport.dev/creator" = var.user
      "env"                  = var.env
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
  source             = "../modules/network"
  cidr_vpc           = "10.0.0.0/16"
  cidr_subnet        = "10.0.1.0/24"
  cidr_public_subnet = "10.0.0.0/24"
  env                = var.env
}

module "mcp_stdio_app" {
  source = "../modules/mcp-stdio-app"

  env              = var.env
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version

  ami_id             = data.aws_ami.linux.id
  instance_type      = var.instance_type
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]

  app_name        = "mcp-everything"
  app_description = "MCP stdio demo server"
  team            = var.team
}

module "machineid_bot" {
  source = "../modules/machineid-bot"

  bot_name       = "mcp-bot"
  role_name      = "mcp-bot-role"
  allowed_logins = []
  node_labels    = {}
  app_labels = {
    env                              = [var.env]
    "teleport.internal/app-sub-kind" = ["mcp"]
  }
  mcp_tools = ["*"]
}
