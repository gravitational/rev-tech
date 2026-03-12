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

locals {
  user_prefix = lower(split("@", var.user)[0])
  resource_tags = {
    "teleport.dev/creator" = var.user
    "env"                  = var.env
    "Example"              = "server-access-ssh-getting-started"
  }
}

provider "aws" {
  region = var.region # "us-east-2" default in variables.tf

  default_tags {
    tags = {
      "teleport.dev/creator" = var.user
      "env"                  = var.env
      "team"                 = var.team
      "ManagedBy"            = "terraform"
      "Example"              = "server-access-ssh-getting-started"
    }
  }
}

provider "teleport" {
  # var.proxy_address is host only (no scheme, no port)
  addr = "${var.proxy_address}:443"
}

# Most recent Amazon Linux 2023 AMI (x86_64, HVM)
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

# ---------------------------------------------------------------------------
# Network: sources config from network module
# ---------------------------------------------------------------------------

module "network" {
  # Resolves to: templates/teleport-terraform/modules/network
  source = "../../modules/network"

  name_prefix        = "${local.user_prefix}-${var.env}"
  tags               = local.resource_tags
  env                = var.env
  cidr_vpc           = var.cidr_vpc
  cidr_subnet        = var.cidr_subnet
  cidr_public_subnet = var.cidr_public_subnet

  # RDS-related flags left at defaults:
  # create_secondary_subnet = false
  # cidr_secondary_subnet  = ""
  # create_db_subnet_group = false
}

# ---------------------------------------------------------------------------
# SSH nodes: sources config for ssh nodes teleport will be installed on
# ---------------------------------------------------------------------------

module "ssh_nodes" {
  # Resolves to: templates/teleport-terraform/modules/ssh-node
  source = "../../modules/ssh-node"

  env              = var.env # "dev" default in variables.tf
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  team             = var.team
  user             = var.user

  tags          = local.resource_tags
  agent_count   = var.agent_count # "3" default in variables.tf
  ami_id        = data.aws_ami.linux.id
  instance_type = var.instance_type # "t3.micro" default in variables.tf

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
