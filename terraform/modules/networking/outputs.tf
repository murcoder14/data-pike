# Networking Module - Outputs

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidr_blocks" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "flink_security_group_id" {
  description = "ID of the Flink application security group"
  value       = aws_security_group.flink.id
}

output "rds_security_group_id" {
  description = "ID of the RDS PostgreSQL security group"
  value       = aws_security_group.rds.id
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 gateway VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "kinesis_vpc_endpoint_id" {
  description = "ID of the Kinesis interface VPC endpoint"
  value       = aws_vpc_endpoint.kinesis.id
}

output "private_route_table_id" {
  description = "ID of the private subnet route table"
  value       = aws_route_table.private.id
}
