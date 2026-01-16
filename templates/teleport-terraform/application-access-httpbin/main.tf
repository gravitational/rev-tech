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

module "httpbin_app" {
  source             = "../../modules/app_httpbin"
  env                = var.env
  user               = var.user
  proxy_address      = var.proxy_address
  teleport_version   = var.teleport_version
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.micro"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "httpbin_registration" {
  source        = "../../modules/registration"
  resource_type = "app"
  name          = "httpbin-${var.env}"
  description   = "Internal HTTP test app using httpbin"
  uri           = "http://localhost:80"
  public_addr   = "httpbin-${var.env}.${var.proxy_address}"
  labels = {
    tier               = var.env
    "teleport.dev/app" = "httpbin"
  }
  rewrite_headers = [
    "Host: httpbin-${var.env}.${var.proxy_address}",
    "Origin: https://httpbin-${var.env}.${var.proxy_address}"
  ]
  insecure_skip_verify = true
}
