terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.7.0"
    }
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 18.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
  }
}

locals {
  tags = merge(var.tags, { Name : var.name })
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "this" {}

resource "tls_private_key" "this" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "this" {
  key_name   = var.name
  public_key = tls_private_key.this.public_key_openssh

  tags = var.tags
}

resource "local_sensitive_file" "ssh_prv_key" {
  content  = tls_private_key.this.private_key_openssh
  filename = "${path.module}/id_ed25519"
}