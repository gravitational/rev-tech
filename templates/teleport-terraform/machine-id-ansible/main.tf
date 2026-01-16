terraform {
  required_version = ">= 1.2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99"
    }
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 17.0"
    }
    random = {
      source  = "hashicorp/random"
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

module "network" {
  source             = "../../modules/network"
  cidr_vpc           = "10.0.0.0/16"
  cidr_subnet        = "10.0.1.0/24"
  cidr_public_subnet = "10.0.0.0/24"
  env                = var.env
}

module "machineid_ansible" {
  source = "../../modules/machineid_ansible"

  env                = var.env
  user               = var.user
  proxy_address      = var.proxy_address
  teleport_version   = var.teleport_version
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}