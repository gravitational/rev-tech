# Module: kube-discovery-agent
#
# Deploys a single EC2 instance running the Teleport agent with both
# kubernetes_service and discovery_service enabled.
#
# The discovery_service scans the account for EKS clusters tagged with
# var.eks_tag_key=var.eks_tag_value and auto-enrolls them by creating EKS
# access entries (requires EKS 1.23+ and Teleport 15+). The kubernetes_service
# on the same instance proxies connections to every discovered cluster.
#
# Pre-requisite: tag target EKS clusters so the agent can find them:
#   aws eks tag-resource \
#     --resource-arn <arn:aws:eks:REGION:ACCOUNT:cluster/NAME> \
#     --tags teleport-discovery=enabled

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
  user              = lower(split("@", var.user)[0])
  name              = "${local.user}-kube-discovery-${var.env}"
  group_name        = "${var.env}-${var.team}"
  discovery_regions = var.discovery_regions != null ? var.discovery_regions : [var.region]
}

# ---------------------------------------------------------------------------
# Teleport provision token.
# ---------------------------------------------------------------------------
resource "random_string" "token" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "agent" {
  version = "v2"
  spec = {
    roles = ["Node", "Kube", "Discovery"]
    name  = random_string.token.result
  }
  metadata = {
    expires = timeadd(timestamp(), "24h")
  }
  lifecycle {
    ignore_changes = [metadata]
  }
}

# ---------------------------------------------------------------------------
# IAM: instance role with EKS discovery + auto-enrollment permissions.
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

resource "aws_iam_role_policy" "eks_discovery" {
  name = "eks-discovery"
  role = aws_iam_role.agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Discover: list and describe EKS clusters in the account.
        Sid    = "EKSDiscovery"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
        ]
        Resource = ["*"]
      },
      {
        # Auto-enroll: create and manage EKS access entries so Teleport can
        # authenticate to each discovered cluster without touching aws-auth.
        Sid    = "EKSAutoEnroll"
        Effect = "Allow"
        Action = [
          "eks:CreateAccessEntry",
          "eks:DeleteAccessEntry",
          "eks:DescribeAccessEntry",
          "eks:AssociateAccessPolicy",
          "eks:DisassociateAccessPolicy",
          "eks:ListAccessEntries",
          "eks:ListAssociatedAccessPolicies",
        ]
        Resource = ["*"]
      },
      {
        # Connect: call the Kubernetes API through the EKS endpoint.
        Sid      = "EKSAPIAccess"
        Effect   = "Allow"
        Action   = ["eks:AccessKubernetesApi"]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "agent" {
  name = local.name
  role = aws_iam_role.agent.name
}

# ---------------------------------------------------------------------------
# EC2: Teleport agent instance.
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
    teleport_version  = var.teleport_version
    proxy_address     = var.proxy_address
    token             = teleport_provision_token.agent.metadata.name
    env               = var.env
    team              = var.team
    discovery_group   = local.group_name
    eks_tag_key       = var.eks_tag_key
    eks_tag_value     = var.eks_tag_value
    discovery_regions = local.discovery_regions
  })

  tags = merge(var.tags, {
    Name = local.name
  })

  # Ensure the provision token exists in Teleport before the instance boots.
  depends_on = [teleport_provision_token.agent]
}
