# Profile: Cloud-Native Apps
#
# Prospect archetype: modern cloud shop running containerized apps, using AWS
# services (RDS, AWS Console), and working with CI/CD automation. Common in
# SaaS companies and tech-forward enterprises.
#
# Demonstrates:
#   - Application Access: Grafana dashboard (the "internal tools" story)
#   - Application Access: HTTPBin (quick header inspection / JWT demo)
#   - Database Access: RDS MySQL with IAM auth + auto user provisioning
#   - Application Access: AWS Console (role-based AWS Console federation)
#
# Deploy:
#   export TF_VAR_proxy_address=myorg.teleport.sh
#   export TF_VAR_user=you@company.com
#   export TF_VAR_teleport_version=18.0.0
#   export TF_VAR_aws_account_id=$(aws sts get-caller-identity --query Account --output text)
#   terraform init && terraform apply
#
# Teardown:
#   terraform destroy

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
      "Profile"              = "cloud-native-apps"
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
    "Profile"              = "cloud-native-apps"
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

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Shared network — one VPC with secondary subnet for RDS.
# ---------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  name_prefix             = "${local.user_prefix}-${var.env}"
  tags                    = local.resource_tags
  env                     = var.env
  cidr_vpc                = var.cidr_vpc
  cidr_subnet             = var.cidr_subnet
  cidr_public_subnet      = var.cidr_public_subnet
  create_secondary_subnet = true
  cidr_secondary_subnet   = var.cidr_secondary_subnet
  create_db_subnet_group  = true
}

# ---------------------------------------------------------------------------
# Grafana: internal dashboard — good for JWT demo.
# ---------------------------------------------------------------------------
module "grafana" {
  source = "../../modules/app-grafana"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.small"
  tags             = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "grafana_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "app"
  name          = "grafana-${var.env}"
  description   = "Grafana dashboard for ${var.env}"
  uri           = "http://localhost:3000"
  public_addr   = "grafana-${var.env}.${var.proxy_address}"
  labels = {
    env                = var.env
    team               = var.team
    "teleport.dev/app" = "grafana"
  }
  rewrite_headers      = ["Host: grafana-${var.env}.${var.proxy_address}", "Origin: https://grafana-${var.env}.${var.proxy_address}"]
  insecure_skip_verify = true
}

# ---------------------------------------------------------------------------
# HTTPBin: instant header/JWT inspection.
# ---------------------------------------------------------------------------
module "httpbin" {
  source = "../../modules/app-httpbin"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.micro"
  tags             = local.resource_tags

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "httpbin_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "app"
  name          = "httpbin-${var.env}"
  description   = "HTTP test app for ${var.env}"
  uri           = "http://localhost:80"
  public_addr   = "httpbin-${var.env}.${var.proxy_address}"
  labels = {
    env                = var.env
    team               = var.team
    "teleport.dev/app" = "httpbin"
  }
  rewrite_headers      = ["Host: httpbin-${var.env}.${var.proxy_address}", "Origin: https://httpbin-${var.env}.${var.proxy_address}"]
  insecure_skip_verify = true
}

# ---------------------------------------------------------------------------
# RDS MySQL with IAM auth + auto user provisioning.
# ---------------------------------------------------------------------------
module "rds_mysql" {
  source = "../../modules/rds-mysql"

  env                  = var.env
  team                 = var.team
  user                 = var.user
  proxy_address        = var.proxy_address
  teleport_version     = var.teleport_version
  region               = var.region
  ami_id               = data.aws_ami.linux.id
  vpc_id               = module.network.vpc_id
  db_subnet_group_name = module.network.db_subnet_group_name
  subnet_id            = module.network.subnet_id
  security_group_ids   = [module.network.security_group_id]
}

# ---------------------------------------------------------------------------
# AWS Console app access.
# ---------------------------------------------------------------------------
module "aws_console_host" {
  source = "../../modules/app-aws-console-host"

  user                 = var.user
  proxy_address        = var.proxy_address
  teleport_version     = var.teleport_version
  ami_id               = data.aws_ami.linux.id
  instance_type        = "t3.micro"
  tags                 = local.resource_tags
  host_env             = var.env
  host_team            = var.team
  app_env              = var.env
  app_a_name           = "awsconsole-${var.env}"
  app_a_public_addr    = "awsconsole-${var.env}.${var.proxy_address}"
  app_a_uri            = "https://console.aws.amazon.com/ec2/v2/home"
  app_a_aws_account_id = data.aws_caller_identity.current.account_id
  app_a_team           = var.team
  assume_role_arns     = var.console_role_arns

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
