# Module: ec2-discovery-agent
#
# Deploys a Teleport Discovery Service agent that scans the AWS account for EC2
# instances tagged with var.ec2_tag_key=var.ec2_tag_value and auto-enrolls them
# via SSM. Target instances join the Teleport cluster using IAM joining — no
# pre-shared secrets or manual token passing required.
#
# How it works:
#   1. The discovery agent finds tagged EC2 instances via DescribeInstances.
#   2. For each new instance, it runs the TeleportDiscoveryInstaller SSM document.
#   3. The SSM document installs Teleport on the target and configures it to join
#      using the IAM token created here.
#   4. The target's IAM role is validated by the Teleport auth server — no token
#      value is ever exchanged.
#
# Pre-requisite: tag target EC2 instances:
#   aws ec2 create-tags \
#     --resources <instance-id> \
#     --tags Key=teleport-discovery,Value=enabled

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
    teleport = {
      source = "terraform.releases.teleport.dev/gravitational/teleport"
    }
  }
}

locals {
  user       = lower(split("@", var.user)[0])
  name       = "${local.user}-ec2-discovery-${var.env}"
  group_name = "${var.env}-${var.team}"
  token_name = "ec2-iam-${var.env}"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Teleport tokens.
# ---------------------------------------------------------------------------

# Discovery agent token — short-lived secret token used only for the agent
# to register itself with the Teleport cluster.
resource "random_string" "agent_token" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "agent" {
  version = "v2"
  spec = {
    roles = ["Node", "Discovery"]
    name  = random_string.agent_token.result
  }
  metadata = {
    expires = timeadd(timestamp(), "8h")
  }
  lifecycle {
    ignore_changes = [metadata]
  }
}

# IAM join token — permanent token used by auto-discovered EC2 instances.
# No secret value; the target instance's IAM role is the credential.
resource "teleport_provision_token" "ec2_iam" {
  version = "v2"
  metadata = {
    name = local.token_name
  }
  spec = {
    roles       = ["Node"]
    join_method = "iam"
    allow = [
      {
        aws_account = data.aws_caller_identity.current.account_id
        aws_arn     = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${var.target_iam_role_name}/*"
      }
    ]
  }
}

# ---------------------------------------------------------------------------
# IAM: discovery agent role.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "agent" {
  name = local.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "ec2_discovery" {
  name = "ec2-discovery"
  role = aws_iam_role.agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Find target EC2 instances by tag.
        Sid    = "EC2Discover"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeInstanceStatus",
        ]
        Resource = ["*"]
      },
      {
        # Send and monitor the Teleport installer SSM command on target instances.
        Sid    = "SSMInstall"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          # Create/update the TeleportDiscoveryInstaller document (self-hosted clusters).
          "ssm:CreateDocument",
          "ssm:DeleteDocument",
          "ssm:DescribeDocument",
          "ssm:GetDocument",
          "ssm:UpdateDocument",
        ]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "agent" {
  name = local.name
  role = aws_iam_role.agent.name
}

# ---------------------------------------------------------------------------
# EC2: Teleport discovery agent instance.
# ---------------------------------------------------------------------------
resource "aws_instance" "agent" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.agent.name

  # Teleport nodes register via outbound reverse tunnel — no public IP needed.
  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 30 # required for AMZN Linux 2023 AMI EBS size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/userdata.tpl", {
    proxy_address    = var.proxy_address
    teleport_version = var.teleport_version
    token            = teleport_provision_token.agent.metadata.name
    region           = var.region
    env              = var.env
    team             = var.team
    discovery_group  = local.group_name
    join_token_name  = local.token_name
    ec2_tag_key      = var.ec2_tag_key
    ec2_tag_value    = var.ec2_tag_value
  })

  tags = merge(var.tags, {
    Name = local.name
  })

  depends_on = [teleport_provision_token.ec2_iam]
}
