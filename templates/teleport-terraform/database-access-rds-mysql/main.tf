terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99"
    }
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 17.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "teleport.dev/creator" = var.user
      "tier"                 = var.env
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
  source = "../../modules/rds_mysql"

  env                  = var.env
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

output "rds_endpoint" {
  value = module.rds_mysql.rds_endpoint
}

output "connection_instructions" {
  value = <<-EOF
    1. Connect to Teleport cluster: tsh login --proxy=${var.proxy_address}:443
    2. List available databases: tsh db ls
    3. Connect to database: tsh db connect rds-mysql-${var.env}
    4. Auto user creation is enabled - users will be created automatically on first connection
    5. Users are assigned permissions based on their Teleport roles
  EOF
}