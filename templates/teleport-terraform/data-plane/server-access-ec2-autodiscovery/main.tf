# Data-plane template: server-access-ec2-autodiscovery
#
# Demonstrates Teleport's EC2 auto-discovery using SSM + IAM joining.
# A Discovery Service agent scans for tagged EC2 instances and automatically
# installs Teleport on them via SSM — no manual token passing, no pre-baked
# AMIs, no user_data Teleport config on the targets.
#
# What gets created:
#   - Discovery agent EC2 (runs Teleport discovery_service)
#   - Target EC2 instances (bare AL2023, tagged, no Teleport pre-installed)
#   - IAM role for targets with SSM permissions (for receiving the installer)
#   - IAM join token (no secret — targets authenticate via their IAM role)
#
# Deploy:
#   export TF_VAR_proxy_address=myorg.teleport.sh
#   export TF_VAR_user=you@company.com
#   export TF_VAR_teleport_version=18.0.0
#   terraform init && terraform apply
#
# After apply, the discovery agent enrolls the target instances within ~60 s.

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
      "Example"              = "server-access-ec2-autodiscovery"
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
    "Example"              = "server-access-ec2-autodiscovery"
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

# ---------------------------------------------------------------------------
# Target instances: bare EC2s that the discovery agent will auto-enroll.
# No Teleport user_data — the SSM installer handles everything.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "target" {
  name = "${local.user_prefix}-ec2-discovery-target-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.resource_tags
}

# AmazonSSMManagedInstanceCore gives the SSM agent everything it needs to
# receive commands from the discovery agent (no custom policy required).
resource "aws_iam_role_policy_attachment" "target_ssm" {
  role       = aws_iam_role.target.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "target" {
  name = "${local.user_prefix}-ec2-discovery-target-${var.env}"
  role = aws_iam_role.target.name
}

resource "aws_instance" "target" {
  count                  = var.target_count
  ami                    = data.aws_ami.linux.id
  instance_type          = "t3.micro"
  subnet_id              = module.network.subnet_id
  vpc_security_group_ids = [module.network.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.target.name

  # Teleport nodes register via outbound reverse tunnel — no public IP needed.
  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  root_block_device {
    encrypted = true
  }

  # The discovery tag tells the agent to enroll this instance.
  # All other AWS tags are automatically surfaced as Teleport node labels.
  tags = merge(local.resource_tags, {
    Name                = "${local.user_prefix}-target-${var.env}-${count.index + 1}"
    (var.ec2_tag_key)   = var.ec2_tag_value
    "teleport.dev/env"  = var.env
    "teleport.dev/team" = var.team
  })
}

# ---------------------------------------------------------------------------
# Discovery agent: finds tagged instances and installs Teleport via SSM.
# ---------------------------------------------------------------------------
module "ec2_discovery" {
  source = "../../modules/ec2-discovery-agent"

  env                  = var.env
  team                 = var.team
  user                 = var.user
  proxy_address        = var.proxy_address
  teleport_version     = var.teleport_version
  region               = var.region
  ami_id               = data.aws_ami.linux.id
  instance_type        = "t3.small"
  tags                 = local.resource_tags
  ec2_tag_key          = var.ec2_tag_key
  ec2_tag_value        = var.ec2_tag_value
  target_iam_role_name = aws_iam_role.target.name

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
