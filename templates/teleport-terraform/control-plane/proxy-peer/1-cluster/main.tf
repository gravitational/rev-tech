##################################################################################
# PROVIDERS
##################################################################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99"
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

##################################################################################
# DATA SOURCES
##################################################################################
# Amazon Linux 2023 AMI (used for aws cli/s3 workflow).
data "aws_ami" "main" {
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

locals {
  username = lower(split("@", var.user)[0])
}

##################################################################################
# RESOURCES
##################################################################################
# Networking
resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_security_group" "main" {
  name        = "${local.username}_linux_teleport_network"
  description = "allows proxy peered setup for self hosted deployment managed by ${local.username}"
  vpc_id      = aws_vpc.main.id

  ingress { # multiplexed port for teleport; allows remote HTTPS access and agent joining
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress { # allows proxies to peer
    from_port   = 3021
    to_port     = 3021
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
  ingress { # allows peers to dial auth
    from_port   = 3025
    to_port     = 3025
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "main" {
  cidr_block              = var.subnet
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Storage
resource "aws_s3_bucket" "main" {
  bucket        = "${local.username}proxypeers"
  force_destroy = true
}

# IAM
resource "aws_iam_role" "ec2_role" {
  name = "${local.username}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_access" {
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ],
        Resource = "${aws_s3_bucket.main.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.username}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
