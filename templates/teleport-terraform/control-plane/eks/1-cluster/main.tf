# 1-eks-cluster/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "teleport.dev/creator" = var.user
      "Purpose"              = "demo"
      "ManagedBy"            = "terraform"
      name                   = var.name
    }
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

# Improved VPC module with better defaults
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for index, az in local.azs : cidrsubnet(local.vpc_cidr, 4, index)]
  public_subnets  = [for index, az in local.azs : cidrsubnet(local.vpc_cidr, 8, index + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true # Cost optimization for demos

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# Improved EKS module with better node configuration
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.name}-cluster"
  cluster_version = var.ver_cluster

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_group_defaults = {
    ami_type = "BOTTLEROCKET_x86_64"
    tags = {
      "teleport.dev/creator" = var.user
    }
  }
  eks_managed_node_groups = {
    # Improved node group sizing for demos
    primary = {
      name           = "${var.name}-group-spot"
      instance_types = ["t3.small"] # Smallest to go for Teleport
      capacity_type  = "SPOT"       # Cost optimization
      min_size       = 1
      max_size       = 4
      desired_size   = 2
    }

    stable = {
      name           = "${var.name}-group-stable"
      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND" # Won't be reclaimed
      min_size       = 1
      max_size       = 1
      desired_size   = 1
    }
  }
}

# Improved addons with essential components
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.1"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }
}

# Fixed IRSA for EBS CSI driver (prevents PVC issues)
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix      = "${var.name}-cluster-ebs-csi-driver-"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}