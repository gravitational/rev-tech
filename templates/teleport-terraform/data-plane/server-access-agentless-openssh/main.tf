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
  }
}

locals {
  user_prefix = lower(split("@", var.user)[0])
  resource_tags = {
    "teleport.dev/creator" = var.user
    "env"                  = var.env
    "Example"              = "server-access-agentless-openssh"
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
      "Example"              = "server-access-agentless-openssh"
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

data "aws_caller_identity" "current" {}

##################################################################################
# NETWORK
##################################################################################
module "network" {
  source = "../../modules/network"

  name_prefix        = "${local.user_prefix}-${var.env}"
  tags               = local.resource_tags
  env                = var.env
  cidr_vpc           = var.cidr_vpc
  cidr_subnet        = var.cidr_subnet
  cidr_public_subnet = var.cidr_public_subnet
}

##################################################################################
# SECURITY GROUP RULE — allow SSH from the Teleport proxy
#
# The network module SG allows traffic only within the VPC. For agentless SSH
# the Teleport proxy (external) must TCP-connect to port 22 directly.
# Auth is certificate-only (Teleport user CA), so opening 22/tcp is safe.
##################################################################################
resource "aws_security_group_rule" "ssh_from_teleport_proxy" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.network.security_group_id
  description       = "SSH from Teleport proxy (CA cert auth only)"
}

##################################################################################
# EC2 INSTANCES — agentless (no Teleport agent installed)
#
# Userdata downloads Teleport's user CA from the proxy's unauthenticated API
# and configures sshd to trust it. The Teleport proxy then routes SSH sessions
# to these hosts using the registered node addresses.
##################################################################################
resource "aws_instance" "node" {
  count                       = var.node_count
  ami                         = data.aws_ami.linux.id
  instance_type               = var.instance_type
  subnet_id                   = module.network.public_subnet_id
  vpc_security_group_ids      = [module.network.security_group_id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/userdata.tpl", {
    proxy_address = var.proxy_address
    login         = var.ssh_login
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.resource_tags, {
    Name = "${local.user_prefix}-${var.env}-agentless-${count.index}"
    env  = var.env
    team = var.team
  })
}

##################################################################################
# TELEPORT NODE REGISTRATION
#
# teleport_server registers the instances in Teleport as agentless OpenSSH nodes.
# Teleport proxies SSH sessions to these hosts using the registered addr.
#
# For EC2 instances in private subnets, use sub_kind = "openssh-ec2-ice" with
# an AWS OIDC integration and an EC2 Instance Connect Endpoint — see README.
##################################################################################
resource "teleport_server" "node" {
  count    = var.node_count
  version  = "v2"
  sub_kind = "openssh"

  metadata = {
    name = "${data.aws_caller_identity.current.account_id}-${aws_instance.node[count.index].id}"
    labels = {
      env  = var.env
      team = var.team
    }
  }

  spec = {
    addr     = "${aws_instance.node[count.index].public_ip}:22"
    hostname = "agentless-${count.index}.${var.env}"
  }

  depends_on = [aws_instance.node]
}
