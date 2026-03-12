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
  source             = "../../modules/network"
  env                = var.env
  cidr_vpc           = var.cidr_vpc
  cidr_subnet        = var.cidr_subnet
  cidr_public_subnet = var.cidr_public_subnet
}

module "httpbin_app" {
  source             = "../../modules/app-httpbin"
  env                = var.env
  user               = var.user
  team               = var.team
  proxy_address      = var.proxy_address
  teleport_version   = var.teleport_version
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.micro"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "httpbin_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "app"
  name          = "httpbin-${var.env}"
  description   = "Internal HTTP test app using httpbin"
  uri           = "http://localhost:80"
  public_addr   = "httpbin-${var.env}.${var.proxy_address}"
  labels = {
    env                = var.env
    team               = var.team
    "teleport.dev/app" = "httpbin"
  }
  rewrite_headers = [
    "Host: httpbin-${var.env}.${var.proxy_address}",
    "Origin: https://httpbin-${var.env}.${var.proxy_address}"
  ]
  insecure_skip_verify = true
}
