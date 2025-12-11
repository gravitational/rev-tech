terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {
  name_prefix = var.name_prefix != "" ? var.name_prefix : var.env
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.cidr_public_subnet
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-subnet"
  })
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.cidr_subnet
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-subnet"
  })
}

# Additional private subnet for RDS (when needed)
resource "aws_subnet" "private_secondary" {
  count                   = var.create_secondary_subnet ? 1 : 0
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.cidr_secondary_subnet
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-subnet-secondary"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-eip"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-gateway"
  })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_secondary" {
  count          = var.create_secondary_subnet ? 1 : 0
  subnet_id      = aws_subnet.private_secondary[0].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "default" {
  name        = "${local.name_prefix}-default-sg"
  description = "Allow all inbound traffic from VPC CIDR"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.cidr_vpc]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-default-sg"
  })
}

# Optional: DB Subnet Group for RDS
resource "aws_db_subnet_group" "main" {
  count      = var.create_db_subnet_group ? 1 : 0
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.create_secondary_subnet ? [aws_subnet.private.id, aws_subnet.private_secondary[0].id] : [aws_subnet.private.id, aws_subnet.public.id]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}
