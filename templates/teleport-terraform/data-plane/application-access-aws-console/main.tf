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

module "network" {
  source             = "../../modules/network"
  env                = var.env
  cidr_vpc           = var.cidr_vpc
  cidr_subnet        = var.cidr_subnet
  cidr_public_subnet = var.cidr_public_subnet
}

data "aws_iam_policy_document" "account_a_role_trust" {
  for_each = var.manage_account_a_roles ? var.account_a_roles : {}

  statement {
    sid    = "AllowTeleportAppHostAssume"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = distinct(concat(
        [module.aws_console_host.iam_role_arn],
        each.value.additional_trust_principals
      ))
    }

    actions = ["sts:AssumeRole"]
  }

  dynamic "statement" {
    for_each = each.value.allow_account_root ? [1] : []
    content {
      sid    = "AllowAccountRootAssume"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
      }

      actions = ["sts:AssumeRole"]
    }
  }
}

resource "aws_iam_role" "account_a" {
  for_each = var.manage_account_a_roles ? var.account_a_roles : {}

  name               = each.key
  assume_role_policy = data.aws_iam_policy_document.account_a_role_trust[each.key].json

  tags = {
    "teleport.dev/creator" = var.user
    "env"                  = var.env
    "team"                 = var.team
    "ManagedBy"            = "terraform"
  }
}

locals {
  account_a_role_policy_attachments = flatten([
    for role_name, role_cfg in var.account_a_roles : [
      for policy_arn in role_cfg.policy_arns : {
        key        = "${role_name}|${policy_arn}"
        role_name  = role_name
        policy_arn = policy_arn
      }
    ]
  ])

  managed_account_a_role_arns = [
    for role_name in keys(var.account_a_roles) : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${role_name}"
  ]

  existing_account_a_role_arns = [
    for role_name in keys(var.account_a_roles) : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${role_name}"
  ]

  effective_assume_role_arns = var.manage_account_a_roles ? concat(
    local.managed_account_a_role_arns,
    var.assume_role_arns
    ) : (
    length(var.assume_role_arns) > 0 ? var.assume_role_arns : local.existing_account_a_role_arns
  )
}

resource "aws_iam_role_policy_attachment" "account_a" {
  for_each = var.manage_account_a_roles ? {
    for attachment in local.account_a_role_policy_attachments : attachment.key => attachment
  } : {}

  role       = aws_iam_role.account_a[each.value.role_name].name
  policy_arn = each.value.policy_arn
}

module "aws_console_host" {
  source = "../../modules/app-aws-console-host"

  user               = var.user
  proxy_address      = var.proxy_address
  teleport_version   = var.teleport_version
  ami_id             = data.aws_ami.linux.id
  instance_type      = var.instance_type
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]

  host_env  = var.host_env
  host_team = var.team

  app_env              = var.env
  app_a_name           = var.app_a_name
  app_a_public_addr    = var.app_a_public_addr != "" ? var.app_a_public_addr : "awsa.${var.proxy_address}"
  app_a_uri            = var.app_a_uri
  app_a_aws_account_id = var.app_a_aws_account_id
  app_a_team           = var.app_a_team
  app_b_name           = var.app_b_name
  enable_app_b         = var.enable_app_b
  app_b_public_addr    = var.app_b_public_addr != "" ? var.app_b_public_addr : "awsconsole-b.${var.proxy_address}"
  app_b_uri            = var.app_b_uri
  app_b_aws_account_id = var.app_b_aws_account_id
  app_b_team           = var.app_b_team
  app_b_external_id    = var.app_b_external_id
  assume_role_arns     = local.effective_assume_role_arns
}
