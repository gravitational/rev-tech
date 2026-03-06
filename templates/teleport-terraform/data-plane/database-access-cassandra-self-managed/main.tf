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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
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

data "http" "teleport_db_ca_cert" {
  url = "https://${var.proxy_address}/webapi/auth/export?type=db-client"
}

module "network" {
  source             = "../../modules/network"
  env                = var.env
  cidr_vpc           = var.cidr_vpc
  cidr_subnet        = var.cidr_subnet
  cidr_public_subnet = var.cidr_public_subnet
}

module "cassandra_instance" {
  source             = "../../modules/self-database"
  db_type            = "cassandra"
  db_hostname        = "cassandra.dev.internal"
  env                = var.env
  user               = var.user
  team               = var.team
  proxy_address      = var.proxy_address
  teleport_version   = var.teleport_version
  teleport_db_ca     = data.http.teleport_db_ca_cert.response_body
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.medium"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "cassandra_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "database"
  name          = "cassandra-${var.env}"
  description   = "Self-hosted Cassandra database in ${var.env}"
  protocol      = "cassandra"
  uri           = "localhost:9042"
  ca_cert_chain = module.cassandra_instance.ca_cert
  labels = {
    env  = var.env
    team = var.team
  }
}
