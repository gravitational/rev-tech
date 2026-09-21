terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    teleport = {
      source = "terraform.releases.teleport.dev/gravitational/teleport"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

locals {
  bot_name = "${var.bot_name_prefix}-${random_string.bot_suffix.result}"
  user     = lower(split("@", var.user)[0])
}

data "aws_caller_identity" "current" {}

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

resource "random_string" "bot_suffix" {
  length  = 4
  upper   = false
  special = false
}

module "machineid_bot" {
  source = "../machineid-bot"

  bot_name       = local.bot_name
  role_name      = "ansible-machine-role"
  allowed_logins = ["ec2-user", local.user]
  node_labels    = { "env" = [var.env], "team" = [var.team] }
  # No onboarding key: Teleport generates a one-time registration secret for
  # the token, tbot redeems it on first start, and the keypair is born on the
  # host — Terraform never sees or stores private key material. Recovery uses
  # the module defaults (mode "standard", limit 10) instead of "insecure".
}

# NODE JOIN: iam, not a shared secret.
#
# This was a random_string 32-char bearer token written to /tmp/token on the
# instance and referenced as teleport.auth_token. Three problems, all gone:
#   - a reusable secret delivered through EC2 user data, readable by anything
#     that can reach the instance metadata service
#   - `expires = timeadd(timestamp(), "1h")` put timestamp() in the config, so
#     every plan reported this resource as changed, forever
#   - it is the weakest join method available, on a host that has the strongest
#     one sitting unused
#
# EC2 instances can prove who they are: iam join has the instance sign an STS
# GetCallerIdentity call and Teleport checks the caller against the allow rules
# below. Nothing secret is generated, stored or transmitted, and the token NAME
# is not sensitive -- so user data carries no credential for this path at all.
# Mirrors modules/ec2-discovery-agent, which already joins this way.
#
# metadata.name is set explicitly. The previous version set spec.name, and
# `spec` has no name attribute in the provider schema (checked against
# v18.11.1), so nothing was setting the name that userdata read back out of
# metadata.name.
resource "teleport_provision_token" "main" {
  version = "v2"
  metadata = {
    name        = "${local.bot_name}-node"
    description = "IAC: iam join for the ansible host's SSH service"
  }
  spec = {
    roles       = ["Node"]
    join_method = "iam"
    allow = [
      {
        aws_account = data.aws_caller_identity.current.account_id
        aws_arn     = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.ansible_host.name}/*"
      }
    ]
  }
}

# IAM identity for the instance. iam join needs the host to have SOME role it
# can sign as; the policy is deliberately empty because Teleport reads the
# caller's identity, not its permissions. This also makes converting the BOT
# to iam a small follow-up -- the identity it would need now exists.
resource "aws_iam_role" "ansible_host" {
  name = "${local.bot_name}-host"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "ansible_host" {
  name = "${local.bot_name}-host"
  role = aws_iam_role.ansible_host.name
}

resource "aws_instance" "ansible_host" {
  # Ensure bot role/user resources exist in Teleport before tbot starts on boot.
  depends_on = [module.machineid_bot]

  ami                    = data.aws_ami.linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  # Required by the iam join above -- with no role the instance has no identity
  # to sign with and teleport cannot start.
  iam_instance_profile = aws_iam_instance_profile.ansible_host.name

  user_data = templatefile("${path.module}/userdata.tpl", {
    env                 = var.env
    team                = var.team
    proxy_address       = var.proxy_address
    bot_token           = module.machineid_bot.bot_token
    registration_secret = module.machineid_bot.bot_registration_secret
    node_token          = teleport_provision_token.main.metadata.name
  })

  # ONE lifecycle block, not two. Terraform allows only a single lifecycle
  # block per resource, and this resource had two -- so `terraform validate`
  # failed outright with "Duplicate lifecycle block" and the module could not
  # be used at all. The ami ignore_changes block was added separately from the
  # precondition block and the pair was never validated together.
  lifecycle {
    # Demo hosts keep the AMI they were created with — data.aws_ami uses
    # most_recent, and a new upstream image must not replace healthy
    # instances on the next apply (e.g. mid-event).
    ignore_changes = [ami]

    precondition {
      condition     = module.machineid_bot.bot_registration_secret != null
      error_message = "The bot token exposed no registration secret (provider too old, or an onboarding key was preregistered) — tbot would have nothing to join with."
    }
  }

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

  tags = {
    Name = "${local.user}-${var.env}-${local.bot_name}"
  }
}
