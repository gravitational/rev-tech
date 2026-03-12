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
  source = "../../modules/network"

  env                     = var.env
  cidr_vpc                = var.cidr_vpc
  cidr_subnet             = var.cidr_subnet
  cidr_public_subnet      = var.cidr_public_subnet
  create_secondary_subnet = true
  cidr_secondary_subnet   = var.cidr_secondary_subnet
  create_db_subnet_group  = true
}

module "rds_mysql" {
  source = "../../modules/rds-mysql"

  env                  = var.env
  team                 = var.team
  user                 = var.user
  proxy_address        = var.proxy_address
  teleport_version     = var.teleport_version
  region               = var.region
  vpc_id               = module.network.vpc_id
  db_subnet_group_name = module.network.db_subnet_group_name
  subnet_id            = module.network.subnet_id
  security_group_ids   = [module.network.security_group_id]
  ami_id               = data.aws_ami.linux.id
}
