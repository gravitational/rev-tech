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
  source             = "../../modules/network"
  cidr_vpc           = "10.0.0.0/16"
  cidr_subnet        = "10.0.1.0/24"
  cidr_public_subnet = "10.0.0.0/24"
  env                = var.env
}

module "grafana_app" {
  source             = "../../modules/app_grafana"
  env                = var.env
  user               = var.user
  proxy_address      = var.proxy_address
  teleport_version   = var.teleport_version
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.small"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "grafana_registration" {
  source        = "../../modules/registration"
  resource_type = "app"
  name          = "grafana-${var.env}"
  description   = "Grafana dashboard for ${var.env}"
  uri           = "http://localhost:3000"
  public_addr   = "grafana-${var.env}.${var.proxy_address}"
  labels = {
    tier               = var.env
    "teleport.dev/app" = "grafana"
  }
  rewrite_headers = [
    "Host: grafana-${var.env}.${var.proxy_address}",
    "Origin: https://grafana-${var.env}.${var.proxy_address}"
  ]
  insecure_skip_verify = true
}