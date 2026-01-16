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

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "mysql" {
  identifier = "${local.user}-${var.env}-rds-mysql"

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name                             = var.db_name
  username                            = var.db_username
  password                            = random_password.db_password.result
  iam_database_authentication_enabled = true

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  parameter_group_name = aws_db_parameter_group.mysql.name

  deletion_protection = false
  skip_final_snapshot = true
}

resource "aws_db_parameter_group" "mysql" {
  family = "mysql8.0"
  name   = "${local.user}-${var.env}-rds-mysql-params"

  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.user}-${var.env}-rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = var.security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.user}-${var.env}-rds-sg"
  }
}

# IAM configuration for RDS access
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "ec2_rds_role" {
  name = "${local.user}-${var.env}-ec2-rds-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_rds_policy" {
  name = "${local.user}-${var.env}-ec2-rds-policy"
  role = aws_iam_role.ec2_rds_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.mysql.resource_id}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances"
        ]
        #Resource = [
        #  "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${aws_db_instance.mysql.identifier}"
        #]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_rds_profile" {
  name = "${local.user}-${var.env}-ec2-rds-profile"
  role = aws_iam_role.ec2_rds_role.name
}

resource "random_string" "token" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "db" {
  version = "v2"
  spec = {
    roles = ["Db", "Node"]
    name  = random_string.token.result
  }
  metadata = {
    expires = timeadd(timestamp(), "1h")
  }
}

resource "teleport_database" "rds_mysql" {
  version = "v3"
  metadata = {
    name        = "rds-mysql-${var.env}"
    description = "RDS MySQL with auto user provisioning in ${var.env}"
    labels = {
      tier                     = var.env
      team                     = var.team
      "teleport.dev/origin"    = "dynamic"
      "teleport.dev/db-access" = "auto"
    }
  }
  spec = {
    protocol = "mysql"
    uri      = aws_db_instance.mysql.endpoint
    aws = {
      region = var.region
      rds = {
        instance_id = aws_db_instance.mysql.identifier
      }
    }
    admin_user = {
      name = "teleport-admin"
    }
  }
}

resource "aws_instance" "agent" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.ec2_rds_profile.name

  user_data = templatefile("${path.module}/userdata.tpl", {
    token            = teleport_provision_token.db.metadata.name
    proxy_address    = var.proxy_address
    teleport_version = var.teleport_version
    rds_endpoint     = aws_db_instance.mysql.endpoint
    rds_instance_id  = aws_db_instance.mysql.identifier
    rds_password     = random_password.db_password.result
    region           = var.region
    env              = var.env
    team             = var.team
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

  tags = {
    Name = "${local.user}-${var.env}-rds-mysql-agent"
  }
}