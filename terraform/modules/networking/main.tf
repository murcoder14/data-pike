# Networking Module - VPC, Subnets, Security Groups, VPC Endpoints
#
# Provisions a VPC with private subnets across multiple AZs,
# security groups for Flink and RDS, route tables, and VPC endpoints.

# =============================================================================
# VPC and Private Subnets
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "flink-pipeline-${var.environment}"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "flink-pipeline-private-${var.environment}-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "private"
  }
}

# =============================================================================
# Security Groups
# =============================================================================

resource "aws_security_group" "flink" {
  name_prefix = "flink-app-${var.environment}-"
  description = "Security group for the Flink application"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "flink-app-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_vpc_security_group_egress_rule" "flink_all_outbound" {
  security_group_id = aws_security_group.flink.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "flink-all-outbound-${var.environment}"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "rds-postgres-${var.environment}-"
  description = "Security group for the RDS PostgreSQL instance"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "rds-postgres-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_flink" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Allow PostgreSQL inbound from Flink application"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.flink.id

  tags = {
    Name = "rds-from-flink-${var.environment}"
  }
}

# =============================================================================
# Route Table for Private Subnets
# =============================================================================

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "flink-pipeline-private-rt-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# VPC Endpoints
# =============================================================================

# --- S3 Gateway Endpoint ---

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name        = "flink-pipeline-s3-endpoint-${var.environment}"
    Environment = var.environment
  }
}

# --- Kinesis Interface Endpoint ---

resource "aws_vpc_endpoint" "kinesis" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.kinesis-streams"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.flink.id]
  private_dns_enabled = true

  tags = {
    Name        = "flink-pipeline-kinesis-endpoint-${var.environment}"
    Environment = var.environment
  }
}
