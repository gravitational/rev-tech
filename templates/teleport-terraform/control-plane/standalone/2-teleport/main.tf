##################################################################################
# PROVIDERS & REMOTE STATE
##################################################################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99"
    }
  }
}

data "terraform_remote_state" "cluster" {
  backend = "local" # Change to "s3" if using remote backend
  config = {
    path = "../1-cluster/terraform.tfstate"
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

##################################################################################
# DATA SOURCES
##################################################################################
data "aws_route53_zone" "main" {
  name = var.domain_name
}

locals {
  username = lower(split("@", var.user)[0])
}

##################################################################################
# EC2 — single node (auth + proxy)
##################################################################################
resource "aws_instance" "main" {
  ami                    = data.terraform_remote_state.cluster.outputs.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [data.terraform_remote_state.cluster.outputs.security_group_id]
  subnet_id              = data.terraform_remote_state.cluster.outputs.subnet_id
  iam_instance_profile   = data.terraform_remote_state.cluster.outputs.instance_profile_name

  user_data = templatefile("${path.module}/config/userdata", {
    bucket           = data.terraform_remote_state.cluster.outputs.bucket_name
    license          = var.license_path != "" ? file(var.license_path) : ""
    proxy_address    = var.proxy_address
    teleport_version = var.teleport_version
    user             = var.user
    env              = var.env
    team             = var.team
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 30 # AL2023 AMI requires >= 30GB
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${local.username}-teleport-standalone"
    Role = "auth+proxy"
  }
}

##################################################################################
# DNS
##################################################################################
resource "aws_route53_record" "cluster" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.proxy_address
  type    = "A"
  ttl     = "300"
  records = [aws_instance.main.public_ip]
}

resource "aws_route53_record" "wildcard" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "*.${var.proxy_address}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.main.public_ip]
}

##################################################################################
# OUTPUTS
##################################################################################
