##################################################################################
# RDS AURORA SERVERLESS v2 (PostgreSQL) — Access Graph database
##################################################################################

# Subnet group using the EKS private subnets
resource "aws_db_subnet_group" "access_graph" {
  name        = "teleport-access-graph-${var.env}"
  subnet_ids  = data.terraform_remote_state.eks.outputs.private_subnets
  description = "Subnet group for Teleport Access Graph PostgreSQL"

  tags = {
    env  = var.env
    team = var.team
  }
}

# Security group: allow PostgreSQL only from within the VPC
resource "aws_security_group" "access_graph_db" {
  name        = "teleport-access-graph-db-${var.env}"
  description = "Allow PostgreSQL from EKS worker nodes"
  vpc_id      = data.terraform_remote_state.eks.outputs.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "PostgreSQL from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    env  = var.env
    team = var.team
  }
}

# Aurora Serverless v2 PostgreSQL cluster
resource "aws_rds_cluster" "access_graph" {
  cluster_identifier     = "teleport-access-graph-${var.env}"
  engine                 = "aurora-postgresql"
  engine_mode            = "provisioned"
  engine_version         = "16.4"
  database_name          = "access_graph"
  master_username        = "access_graph"
  master_password        = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.access_graph.name
  vpc_security_group_ids = [aws_security_group.access_graph_db.id]
  skip_final_snapshot    = true
  deletion_protection    = false

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 4.0
  }

  tags = {
    env  = var.env
    team = var.team
  }
}

# Single Aurora Serverless v2 instance
resource "aws_rds_cluster_instance" "access_graph" {
  identifier         = "teleport-access-graph-${var.env}-1"
  cluster_identifier = aws_rds_cluster.access_graph.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.access_graph.engine
  engine_version     = aws_rds_cluster.access_graph.engine_version

  tags = {
    env  = var.env
    team = var.team
  }
}
