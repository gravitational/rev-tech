##################################################################################
# PROVIDERS & REMOTE STATE
##################################################################################
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# Read EKS cluster info from remote state (NO MANUAL COORDINATION)
data "terraform_remote_state" "eks" {
  backend = "local" # Change to "s3" if using remote backend
  config = {
    path = "../1-cluster/terraform.tfstate"
    # For S3 backend:
    # bucket = "your-state-bucket"
    # key    = "eks-cluster/terraform.tfstate"
    # region = var.region
  }
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name]
    command     = "aws"
  }
}

provider "kubectl" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name]
    command     = "aws"
  }
}

data "kubernetes_namespace" "teleport_cluster" {
  metadata {
    name = var.teleport_namespace
  }
}
