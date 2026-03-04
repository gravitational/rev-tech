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
  user = lower(split("@", var.user)[0])
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "allow_assume_roles" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = var.assume_role_arns
  }
}

resource "aws_iam_role" "app_host" {
  name               = "${local.user}-${var.host_env}-aws-console-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy" "allow_assume_roles" {
  name   = "allow-assume-roles"
  role   = aws_iam_role.app_host.id
  policy = data.aws_iam_policy_document.allow_assume_roles.json
}

resource "aws_iam_instance_profile" "app_host" {
  name = "${local.user}-${var.host_env}-aws-console-host"
  role = aws_iam_role.app_host.name
}

resource "random_string" "token" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "app_host" {
  version = "v2"
  metadata = {
    expires = timeadd(timestamp(), "8h")
  }
  spec = {
    roles = ["App", "Node"]
    name  = random_string.token.result
  }
  # timestamp() changes on every plan, causing perpetual drift noise.
  # The token only needs to live long enough for the instance to boot and register.
  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "aws_instance" "app_host" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  # Teleport nodes register via outbound reverse tunnel — no public IP needed.
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.app_host.name

  user_data = templatefile("${path.module}/userdata.tpl", {
    name                 = "${var.host_env}-aws-console-host"
    token                = teleport_provision_token.app_host.metadata.name
    proxy_address        = var.proxy_address
    teleport_version     = var.teleport_version
    host_env             = var.host_env
    host_team            = var.host_team
    app_env              = var.app_env
    app_a_name           = var.app_a_name
    app_a_public_addr    = var.app_a_public_addr
    app_a_uri            = var.app_a_uri
    app_a_aws_account_id = var.app_a_aws_account_id
    app_a_team           = var.app_a_team
    app_b_name           = var.app_b_name
    enable_app_b         = var.enable_app_b
    app_b_public_addr    = var.app_b_public_addr
    app_b_uri            = var.app_b_uri
    app_b_aws_account_id = var.app_b_aws_account_id
    app_b_team           = var.app_b_team
    app_b_external_id    = var.app_b_external_id
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

  tags = merge(var.tags, {
    Name = "${local.user}-${var.host_env}-aws-console-host"
  })
}
