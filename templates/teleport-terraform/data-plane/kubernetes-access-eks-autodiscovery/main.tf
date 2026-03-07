# Data-plane template: kubernetes-access-eks-autodiscovery
#
# Deploys a Teleport agent that automatically discovers and enrolls EKS clusters
# tagged with 'teleport-discovery=enabled' (configurable). Uses Teleport's EKS
# auto-enrollment to create EKS access entries — no aws-auth ConfigMap edits,
# no manual kubeconfig setup.
#
# Prerequisites:
#   Tag each EKS cluster you want Teleport to discover:
#     aws eks tag-resource \
#       --resource-arn arn:aws:eks:REGION:ACCOUNT:cluster/CLUSTER-NAME \
#       --tags teleport-discovery=enabled
#
# Requirements: Teleport 15+ and EKS 1.23+ (access entries API).
#
# Deploy:
#   export TF_VAR_proxy_address=myorg.teleport.sh
#   export TF_VAR_user=you@company.com
#   export TF_VAR_teleport_version=18.0.0
#   terraform init && terraform apply

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
      "Example"              = "kubernetes-access-eks-autodiscovery"
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
    "Example"              = "kubernetes-access-eks-autodiscovery"
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

module "network" {
  source = "../../modules/network"

  name_prefix        = "${local.user_prefix}-${var.env}"
  tags               = local.resource_tags
  env                = var.env
  cidr_vpc           = var.cidr_vpc
  cidr_subnet        = var.cidr_subnet
  cidr_public_subnet = var.cidr_public_subnet
}

module "kube_agent" {
  source = "../../modules/kube-discovery-agent"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  region           = var.region
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.small"
  tags             = local.resource_tags

  eks_tag_key       = var.eks_tag_key
  eks_tag_value     = var.eks_tag_value
  discovery_regions = var.discovery_regions

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
