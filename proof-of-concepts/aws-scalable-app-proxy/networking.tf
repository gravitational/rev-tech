data "aws_availability_zones" "this" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}

resource "aws_subnet" "this" {
  for_each = {for i, az in data.aws_availability_zones.this.names: az => i}
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr, 3, each.value)
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = local.tags
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = local.tags
}

resource "aws_route_table_association" "this" {
  for_each = {for i, sb in aws_subnet.this: i => sb}
  route_table_id = aws_route_table.this.id
  subnet_id      = each.value.id
}

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.this.id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = { for i, rule in var.firewall_rules : i + 1 => rule if(rule.ingress) }

  cidr_ipv4         = each.value.cidr
  security_group_id = aws_security_group.this.id
  ip_protocol       = each.value.proto
  from_port         = each.value.from_port
  to_port           = each.value.to_port

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = {
    for i, rule in var.firewall_rules : i + 1 => rule if(!rule.ingress && rule.proto != "-1")
  }

  cidr_ipv4         = each.value.cidr
  security_group_id = aws_security_group.this.id
  ip_protocol       = each.value.proto
  from_port         = each.value.from_port
  to_port           = each.value.to_port

  tags = local.tags
}

# resource "aws_network_interface" "this" {
#   subnet_id       = aws_subnet.this.id
#   security_groups = [aws_security_group.this.id]
#
#   tags = var.tags
# }