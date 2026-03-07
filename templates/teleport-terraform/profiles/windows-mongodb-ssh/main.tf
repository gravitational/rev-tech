# Profile: Windows + MongoDB + SSH
#
# Prospect archetype: traditional enterprise running Windows desktops, MongoDB,
# and Linux SSH servers. Common in financial services, healthcare, and legacy
# enterprise shops that haven't moved fully to cloud-native.
#
# Demonstrates:
#   - Server Access: SSH to Linux nodes (the "how do your admins get to servers?" story)
#   - Database Access: self-hosted MongoDB with TLS + Teleport DB agent
#   - Desktop Access: Windows Server via Teleport Desktop Service
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
      "Profile"              = "windows-mongodb-ssh"
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
    "Profile"              = "windows-mongodb-ssh"
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
# Individual data-plane templates each create their own VPC; profiles share one.
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

# ---------------------------------------------------------------------------
# SSH nodes: 2 Linux servers for the Server Access demo.
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
# MongoDB: self-hosted with TLS + Teleport DB agent.
# ---------------------------------------------------------------------------
data "http" "teleport_db_ca" {
  url = "https://${var.proxy_address}/webapi/auth/export?type=db-client"
}

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
  labels = {
    env  = var.env
    team = var.team
  }
}

# ---------------------------------------------------------------------------
# Windows Desktop Access.
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
